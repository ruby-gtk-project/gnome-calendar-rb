# frozen_string_literal: true

require 'adwaita'
require_relative 'agenda_view'
require_relative 'calendar_list'
require_relative 'date_chooser'
require_relative 'date_time_utils'
require_relative 'event_popover'
require_relative 'month_view'
require_relative 'quick_add_popover'
require_relative 'range'
require_relative 'settings'
require_relative 'style'
require_relative 'sync_indicator'
require_relative 'utils'

# Window is the main window: a collapsible sidebar holding the month chooser
# and the calendar list, and a content pane holding the view stack, its
# header bar and the navigation action bar along the bottom.
#
# The window owns the active date. Every view binds to it, the sidebar's
# chooser binds to it, and the navigation actions move it — which is what
# keeps the sidebar and the view showing the same month.
#
# Two breakpoints reshape it, as upstream's do: under 1000sp the sidebar
# collapses and the view switcher goes to icons; under 700sp only the agenda
# view is left, and the navigation buttons and sidebar button go away.
#
# Ported from upstream's src/gui/gcal-window.blp and
# src/gui/gcal-window.c.
#
class Window
  # Upstream's GcalWindowView order, which the win.change-view action's
  # integer argument indexes.
  MONTH = 0
  WEEK = 1
  AGENDA = 2

  # The icon and tooltip each view wants on the navigation buttons, from
  # upstream's get_previous_date_* / get_next_date_* template callbacks.
  NAVIGATION = {
    'month'  => {
      previous_icon:    'go-previous-symbolic',
      next_icon:        'go-next-symbolic',
      previous_tooltip: 'Previous Month',
      next_tooltip:     'Next Month',
    },
    'agenda' => {
      previous_icon:    'go-previous-symbolic',
      next_icon:        'go-next-symbolic',
      previous_tooltip: 'Yesterday',
      next_tooltip:     'Tomorrow',
    },
  }.freeze

  # Upstream's window actions and the accelerators its ShortcutController
  # binds them to. The change-view entries carry their integer argument in
  # the detailed action name, as GTK's accelerator table expects.
  ACCELERATORS = {
    'win.new-event'       => ['<Control>n'],
    'win.today'           => ['<Control>t', '<Alt>Down', 'Home'],
    'win.previous-date'   => ['<Alt>Left', 'Page_Up'],
    'win.next-date'       => ['<Alt>Right', 'Page_Down'],
    'win.change-view(-1)' => ['<Control>Page_Down'],
    'win.change-view(-2)' => ['<Control>Page_Up'],
    'win.change-view(0)'  => ['<Alt>1'],
    'win.change-view(1)'  => ['<Alt>2'],
    'win.change-view(3)'  => ['<Alt>3'],
    'window.close'        => ['<Control>w'],
    'app.quit'            => ['<Control>q'],
    'app.sync'            => ['<Control>r', 'F5'],
  }.freeze

  attr_reader :active_date, :context

  def initialize(application, context)
    @application = application
    @context = context
    @active_date = DateTimeUtils.start_of_day(Time.now)
    @views = {}
  end

  # Assembles the widget tree once; a second call is a no-op, which is what
  # lets a caller ask for the built window without caring whether it already
  # exists.
  def build
    unless @assembled
      @assembled = assemble
    end
    window
  end

  def assemble
    window.tap do |win|
      win.content = overlay

      overlay.tap do |toasts|
        toasts.child = split_view

        split_view.tap do |view|
          view.sidebar = sidebar_toolbar
          view.content = main_toolbar

          sidebar_toolbar.tap do |toolbar|
            toolbar.add_top_bar(sidebar_header)
            toolbar.content = sidebar_box

            sidebar_box.tap do |box|
              box.append(date_chooser.build)
              box.append(calendar_list.build)
            end
          end

          main_toolbar.tap do |toolbar|
            toolbar.add_top_bar(header_bar)
            toolbar.content = views_stack
            toolbar.add_bottom_bar(action_bar)

            header_bar.tap do |bar|
              bar.pack_start(sidebar_button)
              bar.pack_start(sync_indicator.build)
              bar.title_widget = title_label
              bar.pack_end(menu_button)
            end

            views_stack.tap do |stack|
              stack.add_titled_with_icon(
                month_view.build,
                'month',
                '_Month',
                'calendar-month-symbolic',
              )
              stack.add_titled_with_icon(
                agenda_view.build,
                'agenda',
                '_Agenda',
                'calendar-agenda-symbolic',
              )
              stack.signal_connect('notify::visible-child') { on_view_changed }
            end

            action_bar.tap do |bar|
              bar.pack_start(previous_date_button)
              bar.pack_start(next_date_button)
              bar.pack_start(today_button)
              bar.set_center_widget(view_switcher_bin)
              bar.pack_end(new_event_button)
            end

            view_switcher_bin.tap do |bin|
              bin.child = view_switcher_wide
            end
          end
        end
      end

      @views = { 'month' => month_view, 'agenda' => agenda_view }

      month_view.tap do |view|
        view.on_create_event { |range, _x, _y| show_quick_add(range) }
        view.on_create_event_detailed { |range| show_quick_add(range) }
        view.on_event_activated { |event, widget| show_event(event, widget) }
      end

      agenda_view.tap do |view|
        view.on_create_event { |range, _x, _y| show_quick_add(range) }
        view.on_create_event_detailed { |range| show_quick_add(range) }
        view.on_event_activated { |event, widget| show_event(event, widget) }
      end

      date_chooser.on_day_selected { |date| self.active_date = date }
      quick_add_popover.on_event_created { refresh_views }

      sidebar_button.tap do |button|
        button.signal_connect('toggled') { split_view.show_sidebar = button.active? }
      end

      previous_date_button.tap do |button|
        button.signal_connect('clicked') { go_to_previous_date }
      end

      next_date_button.tap do |button|
        button.signal_connect('clicked') { go_to_next_date }
      end

      today_button.tap do |button|
        button.signal_connect('clicked') { go_to_today }
      end

      new_event_button.tap do |button|
        button.action_name = 'win.new-event'
      end

      win.add_breakpoint(collapse_breakpoint)
      win.add_breakpoint(narrow_breakpoint)

      install_actions
      install_accelerators
      watch_manager
      watch_clock

      restore_active_view
      sync_everything
    end
  end

  def widget = build

  def present
    build.present
    self
  end

  # The active date every view and the sidebar share.
  def active_date=(date)
    @active_date = DateTimeUtils.start_of_day(date)
    date_chooser.active_date = @active_date
    current_view.active_date = @active_date
    update_title
    update_today_enabled
    @active_date
  end

  # Upstream's win.next-date: whatever the current view calls next.
  def go_to_next_date
    self.active_date = current_view.next_date
    self
  end

  def go_to_previous_date
    self.active_date = current_view.previous_date
    self
  end

  def go_to_today
    self.active_date = DateTimeUtils.start_of_day(Time.now)
    self
  end

  # Upstream's on_view_action_activated(): -1 is the next view, -2 the
  # previous, anything else an index, clamped to the views that exist.
  def change_view(index)
    names = @views.keys
    current = names.index(views_stack.visible_child_name) || 0

    target = index
    if index == -1
      target = current + 1
    end
    if index == -2
      target = current - 1
    end

    views_stack.visible_child_name = names[target.clamp(0, names.length - 1)]
    self
  end

  # Shows a toast, which is how upstream reports a failed import or an
  # undoable delete.
  def show_toast(message)
    overlay.add_toast(Adwaita::Toast.new(message))
    self
  end

  # Re-reads the events for every view, which the manager's changes trigger.
  def refresh_views
    @views.each_value(&:refresh)
    date_chooser.events = context.manager.events_in_range(date_chooser_range)
    self
  end

  def window
    @window ||= Adwaita::ApplicationWindow.new(@application).tap do |win|
      win.title = 'Calendar'
      win.set_default_size(*context.settings.window_size)
      win.width_request = 360
      win.height_request = 600
      context.settings.apply_to(win)
    end
  end

  def overlay = @overlay ||= Adwaita::ToastOverlay.new

  def split_view
    @split_view ||= Adwaita::OverlaySplitView.new.tap do |view|
      view.pin_sidebar = true
      view.show_sidebar = false
    end
  end

  def sidebar_toolbar = @sidebar_toolbar ||= Adwaita::ToolbarView.new
  def sidebar_header = @sidebar_header ||= Adwaita::HeaderBar.new
  def sidebar_box = @sidebar_box ||= Gtk::Box.new(:vertical, 0)

  def main_toolbar
    @main_toolbar ||= Adwaita::ToolbarView.new.tap { |view| view.add_css_class('view') }
  end

  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def sidebar_button
    @sidebar_button ||= Gtk::ToggleButton.new.tap do |button|
      button.icon_name = 'sidebar-show-symbolic'
      button.tooltip_text = 'Toggle Sidebar'
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap { |label| label.add_css_class('heading') }
  end

  def menu_button
    @menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'open-menu-symbolic'
      button.tooltip_text = 'Main Menu'
      button.primary = true
      button.menu_model = main_menu
    end
  end

  # Upstream's menu model, section for section.
  def main_menu
    @main_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, Gio::Menu.new.tap { |section| section.append('_Synchronize Calendars', 'app.sync') })
      menu.append_section(nil, settings_menu_section)
      menu.append_section(nil, about_menu_section)
    end
  end

  def settings_menu_section
    @settings_menu_section ||= Gio::Menu.new.tap do |section|
      section.append('_Date & Time Settings…', 'win.open-date-time-settings')
      section.append('_Online Accounts…', 'win.open-online-accounts')
    end
  end

  def about_menu_section
    @about_menu_section ||= Gio::Menu.new.tap do |section|
      section.append('_Keyboard Shortcuts', 'app.shortcuts')
      section.append('_About Calendar', 'app.about')
    end
  end

  def views_stack
    @views_stack ||= Adwaita::ViewStack.new.tap do |stack|
      stack.hexpand = true
      stack.vexpand = true
      stack.add_css_class('view')
    end
  end

  def action_bar = @action_bar ||= Gtk::ActionBar.new

  def previous_date_button
    @previous_date_button ||= Gtk::Button.new(icon_name: 'go-previous-symbolic')
  end

  def next_date_button = @next_date_button ||= Gtk::Button.new(icon_name: 'go-next-symbolic')

  def today_button
    @today_button ||= Gtk::Button.new.tap do |button|
      button.child = Adwaita::ButtonContent.new.tap do |content|
        content.label = '_Today'
        content.use_underline = true
        content.icon_name = 'calendar-today-symbolic'
        content.can_shrink = true
      end
      button.tooltip_text = 'Go to Today'
    end
  end

  def new_event_button
    @new_event_button ||= Gtk::Button.new(icon_name: 'list-add-symbolic').tap do |button|
      button.tooltip_text = 'Add Event'
    end
  end

  def view_switcher_bin = @view_switcher_bin ||= Adwaita::Bin.new

  def view_switcher_wide
    @view_switcher_wide ||= Adwaita::ViewSwitcher.new.tap do |switcher|
      switcher.stack = views_stack
      switcher.policy = :wide
    end
  end

  def view_switcher_narrow
    @view_switcher_narrow ||= Adwaita::InlineViewSwitcher.new.tap do |switcher|
      switcher.stack = views_stack
      switcher.display_mode = :icons
      switcher.add_css_class('flat')
    end
  end

  def month_view = @month_view ||= MonthView.new(context)
  def agenda_view = @agenda_view ||= AgendaView.new(context)
  def sync_indicator = @sync_indicator ||= SyncIndicator.new
  def calendar_list = @calendar_list ||= CalendarList.new(context)
  def quick_add_popover = @quick_add_popover ||= QuickAddPopover.new(context)
  def event_popover = @event_popover ||= EventPopover.new(context)

  def date_chooser
    @date_chooser ||= DateChooser.new(
      active_date:       @active_date,
      split_month_year:  true,
      show_week_numbers: false,
    )
  end

  # Upstream's "max-width: 1000sp" breakpoint.
  def collapse_breakpoint
    @collapse_breakpoint ||= Adwaita::Breakpoint.new(
      Adwaita::BreakpointCondition.parse('max-width: 1000sp'),
    ).tap do |breakpoint|
      breakpoint.add_setter(split_view, 'collapsed', true)
      breakpoint.add_setter(view_switcher_bin, 'child', view_switcher_narrow)
    end
  end

  # Upstream's "max-width: 700sp" breakpoint: agenda only.
  def narrow_breakpoint
    @narrow_breakpoint ||= Adwaita::Breakpoint.new(
      Adwaita::BreakpointCondition.parse('max-width: 700sp'),
    ).tap do |breakpoint|
      breakpoint.add_setter(split_view, 'collapsed', true)
      breakpoint.add_setter(split_view, 'show-sidebar', false)
      breakpoint.add_setter(view_switcher_bin, 'visible', false)
      breakpoint.add_setter(previous_date_button, 'visible', false)
      breakpoint.add_setter(next_date_button, 'visible', false)
      breakpoint.add_setter(sidebar_button, 'visible', false)
    end
  end

  private

    # Upstream's gcal_window_class_init() action entries, minus the ones
    # whose dialogs are not ported yet.
    def install_actions
      {
        'today'                   => -> { go_to_today },
        'next-date'               => -> { go_to_next_date },
        'previous-date'           => -> { go_to_previous_date },
        'new-event'               => -> { show_quick_add(day_range(@active_date)) },
        'open-date-time-settings' => -> { launch_settings_panel('datetime') },
        'open-online-accounts'    => -> { launch_settings_panel('online-accounts') },
      }.each do |name, callback|
        window.add_action(
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect('activate') { callback.call }
          end,
        )
      end

      window.add_action(
        Gio::SimpleAction.new('change-view', GLib::VariantType.new('i')).tap do |action|
          # The Ruby bindings unwrap a GVariant 'activate' parameter on the
          # way in, same as they do on the way out of a property read (see
          # the ruby-gtk-testing skill's recipes.md) — `parameter` here is
          # already a plain Integer, so `.value` raised NoMethodError on
          # every real call to win.change-view, crashing the app the moment
          # anything (the view switcher, an accelerator, this test) invoked
          # it with an argument.
          action.signal_connect('activate') { |_action, parameter| change_view(parameter) }
        end,
      )
      self
    end

    def install_accelerators
      ACCELERATORS.each { |action, accelerators| @application.set_accels_for_action(action, accelerators) }
      self
    end

    # Upstream's win.open-date-time-settings / win.open-online-accounts,
    # which hand off to GNOME Settings over D-Bus.
    def launch_settings_panel(panel)
      Gio::DBusConnection.new(:session).call(
        'org.gnome.Settings',
        '/org/gnome/Settings',
        'org.freedesktop.Application',
        'ActivateAction',
        GLib::Variant.new(['launch-panel', [GLib::Variant.new([panel, {}])], {}]),
      )
      self
    rescue StandardError, NoMethodError
      show_toast('Could not open Settings')
    end

    def watch_manager
      context.manager.on_events_changed { refresh_views }
      context.manager.on_calendar_changed { refresh_views }
      context.manager.on_synchronizing { |syncing| sync_indicator.syncing = syncing }
      self
    end

    def watch_clock
      context.clock.on_day_changed { refresh_views }
      self
    end

    # Upstream's restore of the active-view setting.
    def restore_active_view
      name = Settings::VIEWS[context.settings.active_view_index]
      if @views.key?(name)
        views_stack.visible_child_name = name
      end
      self
    end

    def current_view = @views.fetch(views_stack.visible_child_name, month_view)

    # Upstream's view_changed(): remember the view, point the navigation
    # buttons the right way, and move the new view to the active date.
    def on_view_changed
      name = views_stack.visible_child_name
      context.settings['active-view'] = name
      apply_navigation_labels(name)
      current_view.active_date = @active_date
      update_title
      update_today_enabled
      self
    end

    def apply_navigation_labels(name)
      labels = NAVIGATION.fetch(name, NAVIGATION.fetch('month'))
      previous_date_button.icon_name = labels.fetch(:previous_icon)
      previous_date_button.tooltip_text = labels.fetch(:previous_tooltip)
      next_date_button.icon_name = labels.fetch(:next_icon)
      next_date_button.tooltip_text = labels.fetch(:next_tooltip)
      self
    end

    # Upstream's navigation button title, which names the month on screen.
    def update_title
      title_label.text = "#{Utils.month_name(@active_date.month - 1)} #{@active_date.year}"
      self
    end

    # Upstream's update_today_action_enabled(): Today is pointless when the
    # view is already on this week.
    def update_today_enabled
      now = Time.now
      action = window.lookup_action('today')
      unless action.nil?
        action.enabled = @active_date.year != now.year ||
                         DateTimeUtils.week_of_year(@active_date) != DateTimeUtils.week_of_year(now)
      end
      self
    end

    def show_quick_add(range)
      quick_add_popover.build
      quick_add_popover.show_for(range, current_view_widget)
      self
    end

    # Upstream's "event-activated" handling: a click on an event opens the
    # event popover, pointed at the event widget that was clicked.
    def show_event(event, widget)
      event_popover.show_for(event, widget.widget)
      self
    end

    def current_view_widget
      case current_view
      when AgendaView then agenda_view.root_box
      else month_view.root_box
      end
    end

    def day_range(date)
      CalendarRange.new(date, DateTimeUtils.add_days(date, 1), CalendarRange::DEFAULT)
    end

    def date_chooser_range
      first = Time.new(
        @active_date.year,
        @active_date.month,
        1,
        0,
        0,
        0,
      )
      CalendarRange.new(
        DateTimeUtils.add_days(first, -7),
        DateTimeUtils.add_days(first, 49),
        CalendarRange::DEFAULT,
      )
    end

    # Pushes the active date and the event data through everything once the
    # window is assembled.
    def sync_everything
      apply_navigation_labels(views_stack.visible_child_name)
      self.active_date = @active_date
      refresh_views
      self
    end
end
