# frozen_string_literal: true

# Drives the whole app headlessly: builds the window, creates events through
# the quick-add popover, switches views, navigates dates, toggles calendars,
# opens every dialog, exercises the breakpoints and the sync indicator, and
# screenshots each state.
#
# Why this file exists: a GTK app that loads is not a GTK app that works.
# `ruby -c` passes on code that builds an empty window, and the Ruby bindings
# differ from the C API in ways that only a run reveals.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run --server-args="-screen 0 1920x1080x24" -a \
#     ruby test/drive_gnome_calendar.rb
#
# The explicit --server-args matters here: xvfb-run's default virtual screen
# is too small for this window's 768px default width, so GTK clips the
# window down to it (observed: a 1180x600 request came back as 630x590) and
# every Gtk::Popover anchored inside it then refuses to map at all (#popup
# runs with no error, but #visible? and #mapped? both stay false) — not a
# port bug, a too-small headless display.
#
# The spec suite (empty so far — run through RSpec per the dev-shell banner)
# covers the display-free half, were there any non-widget units isolated
# enough to need no widget at all. What is driven here is what needs a
# widget: the wiring, the state swaps and anything a screenshot can show —
# plus, inline, the handful of model classes (Manager, Calendar, Event,
# CalendarRange, RangeTree, Settings, Utils, DateTimeUtils) that are easiest
# to exercise through the running app's own objects rather than rebuilt in
# isolation.

require 'fileutils'
require 'tmpdir'
require 'json'

# Scratch config/data directories, so a run never reads or writes the real
# user's settings or calendars.
ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('gnome-calendar-config')
ENV['XDG_DATA_HOME'] = Dir.mktmpdir('gnome-calendar-data')

# Seeds a wide starting size (settings.rb's apply_to reads this before the
# window is ever shown). Without this the window opens at its 768-wide
# default, which is itself narrower than the 1000sp breakpoint, so the
# breakpoint the window ships with is *already* applied before the driver
# gets a single tick — there would be no "wide" state left to prove the
# narrow one is a real transition out of.
settings_dir = File.join(ENV['XDG_CONFIG_HOME'], 'gnome-calendar-rb')
FileUtils.mkdir_p(settings_dir)
File.write(
  File.join(settings_dir, 'settings.json'),
  JSON.generate('window-width' => 1400, 'window-height' => 800, 'window-maximized' => false),
)

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'main'
require_relative 'gtk_driver'

SHOTS = File.expand_path('../tmp/shots', __dir__)
FileUtils.rm_rf(SHOTS)

# Turns the main loop over for `ms` milliseconds and comes back, without
# blocking the loop the way Kernel#sleep would.
def pump(ms)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ms / 1000.0)
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    GLib::MainContext.default.iteration(false)
  end
end

# Polls a condition rather than asserting it once, up to ~2s in 50ms slices.
# See the note by the first use of this, by the quick-add Save step, for why:
# a click's effect has shown up anywhere from the same tick to several ticks
# later under this build machine's load, and GtkButton#activate has no async
# step of its own to explain that — it is scheduling jitter, not a feature,
# so this waits it out rather than either asserting blind or loosening what
# is asserted.
def wait_until(&condition)
  40.times do
    return true if condition.call

    pump(50)
  end
  condition.call
end

GtkDriver.drive(App.new, shots: SHOTS) do |d, app|
  d.window { app.window.window }

  d.step('the window builds and shows the month view') do
    d.check('the window is an Adwaita::ApplicationWindow') do
      app.window.window.is_a?(Adwaita::ApplicationWindow)
    end
    d.check('it is the only toplevel') { Gtk::Window.list_toplevels.length == 1 }
    d.check('its title is Calendar') { app.window.window.title == 'Calendar' }
    d.check('the sidebar starts collapsed-shut') { !app.window.split_view.show_sidebar? }
    d.check('the month view is the visible stack child') do
      app.window.views_stack.visible_child_name == 'month'
    end
    d.check('the title label names the current month and year') do
      now = Time.now
      app.window.title_label.text == "#{Utils.month_name(now.month - 1)} #{now.year}"
    end
    d.check('the sync indicator starts empty') { app.window.sync_indicator.stack.visible_child_name == 'empty' }
    d.check('a default Personal calendar was created on startup') do
      app.context.manager.calendars.length == 1 && app.context.manager.calendars.first.name == 'Personal'
    end
    d.check('the sidebar lists it') { app.window.calendar_list.listbox.children.length == 1 }
    d.shot('01-month-view')
  end

  d.step('the sidebar toggle shows and hides the sidebar') do
    app.window.sidebar_button.active = true
    d.check('the split view opened') { app.window.split_view.show_sidebar? }
    d.shot('02-sidebar-open')
    app.window.sidebar_button.active = false
    d.check('it closed again') { !app.window.split_view.show_sidebar? }
  end

  # --- Quick-add popover: creating an event from a click on a day ----------

  d.step("clicking today's cell opens the quick-add popover") do
    # Button#activate declines on a widget that is not mapped, and a plain
    # Gtk::Box like MonthCell#cell carries no default activation at all — the
    # cell's real input path is its GestureClick, so that is what a click
    # would actually fire.
    cell = app.window.month_view.cells.flatten.find(&:selected?)
    cell.click_gesture.signal_emit('released', 1, 5.0, 5.0)
    pump(50)
  end

  d.step('the popover is titled for today and refuses an empty name') do
    app.window.quick_add_popover.then do |popover|
      d.check('the heading says New Event Today') { popover.title_label.text == 'New Event Today' }
      d.check('Save starts insensitive') { !popover.add_button.sensitive? }
      d.check('the default calendar is preselected') do
        popover.calendars_list_box.get_row_at_index(0).equal?(popover.calendars_list_box.selected_row)
      end
      d.shot('03-quick-add-empty')

      popover.summary_entry.text = 'Standup'
      d.check('Save is sensitive once named') { popover.add_button.sensitive? }
    end
  end

  d.step('Save creates the event') do
    app.window.quick_add_popover.add_button.activate
  end

  # A click's effect has landed anywhere from the very same tick to several
  # ticks later under the load of this shared build machine, even though
  # GtkButton#activate is a synchronous call with no async step of its own —
  # confirmed by direct comparison, not assumed. A bounded poll (per the
  # ruby-gtk-testing skill's "wait for a condition" recipe) is the honest
  # fix; a longer fixed pump still occasionally lost the race, and a single
  # fixed tick is what this replaces.
  d.step('the event exists and every view refreshed') do
    wait_until { app.context.manager.events_in_range(app.window.month_view.range).length == 1 }
    d.check('one event exists') { app.context.manager.events_in_range(app.window.month_view.range).length == 1 }
    d.check('its summary is what was typed') do
      app.context.manager.events_in_range(app.window.month_view.range).first.summary == 'Standup'
    end
    d.check("today's cell shows it") do
      app.window.month_view.cells.flatten.find(&:selected?).events.length == 1
    end
    d.shot('04-event-created')
  end

  d.step('switching to the agenda view') do
    app.window.window.lookup_action('change-view').activate(GLib::Variant.new(2, GLib::VariantType.new('i')))
    pump(300)
  end

  d.step('the agenda view also picks up the new event') do
    wait_until { app.window.views_stack.visible_child_name == 'agenda' }
    d.check('the agenda view is now showing') { app.window.views_stack.visible_child_name == 'agenda' }
    d.check('navigation labels switched to Yesterday/Tomorrow') do
      app.window.previous_date_button.tooltip_text == 'Yesterday' &&
        app.window.next_date_button.tooltip_text == 'Tomorrow'
    end
    d.check("today's row is attached") do
      app.window.agenda_view.visible_day_rows.any? { |row| row.day.n_items.positive? }
    end
    d.shot('05-agenda-view')
  end

  d.step('clicking the event in the agenda opens the event popover') do
    row = app.window.agenda_view.day_rows.find { |r| r.day.events.any? { |e| e.summary == 'Standup' } }
    d.check('a day row carries the new event') { !row.nil? }
    # AgendaViewDayRow sets `row.child = EventWidget.new(...).build`, and
    # EventWidget#build returns the button itself, so the row's child *is*
    # the button already — no further `.button` to reach through it.
    unless row.nil?
      row.listbox.first_child.child.activate
      pump(300)
    end
  end

  d.step('the event popover shows the summary and date') do
    wait_until { app.window.event_popover.event&.summary == 'Standup' }
    app.window.event_popover.then do |popover|
      d.check('the popover has the right event') { popover.event&.summary == 'Standup' }
      d.check('the summary label shows it') { popover.summary_label.label == 'Standup' }
      d.check('the date/time label is set') { !popover.date_time_label.label.to_s.empty? }
      d.check('the read-only icon is hidden for a writable calendar') { !popover.read_only_icon.visible? }
      d.check('the action button offers edit, not view') { popover.action_button.icon_name == 'edit-symbolic' }
      d.shot('06-event-popover')
    end
  end

  d.step('the action button closes the popover (no editor wired yet)') do
    app.window.event_popover.action_button.activate
  end

  d.step('it closed') do
    wait_until { !app.window.event_popover.popover.visible? }
    d.check('the popover closed') { !app.window.event_popover.popover.visible? }
  end

  # --- Month view: navigation, overflow popover -----------------------------

  d.step('switching back to the month view') do
    app.window.window.lookup_action('change-view').activate(GLib::Variant.new(0, GLib::VariantType.new('i')))
  end

  d.step('the month view is showing again') do
    wait_until { app.window.views_stack.visible_child_name == 'month' }
    d.check('the month view is showing again') { app.window.views_stack.visible_child_name == 'month' }
  end

  d.step('the next month button moves the active date') do
    @nav_start = app.window.active_date
    app.window.next_date_button.activate
  end

  d.step('it moved forward one month, and the previous button moves back') do
    wait_until { DateTimeUtils.compare_date(app.window.active_date, DateTimeUtils.add_months(@nav_start, 1)).zero? }
    d.check('next month moved the active date forward one month') do
      DateTimeUtils.compare_date(app.window.active_date, DateTimeUtils.add_months(@nav_start, 1)).zero?
    end
    app.window.previous_date_button.activate
  end

  d.step('it is back where it started') do
    wait_until { DateTimeUtils.compare_date(app.window.active_date, @nav_start).zero? }
    d.check('previous month moved it back') { DateTimeUtils.compare_date(app.window.active_date, @nav_start).zero? }
    d.shot('07-after-navigation')
  end

  d.step('the Today button returns to the current month') do
    app.window.next_date_button.activate
    app.window.next_date_button.activate
    app.window.today_button.activate
  end

  d.step('back on the current month') do
    wait_until { DateTimeUtils.compare_date(app.window.active_date, DateTimeUtils.start_of_day(Time.now)).zero? }
    d.check('back on the current month') do
      DateTimeUtils.compare_date(app.window.active_date, DateTimeUtils.start_of_day(Time.now)).zero?
    end
  end

  d.step('three more events on one day fill a cell without overflowing') do
    day = DateTimeUtils.add_days(DateTimeUtils.start_of_day(Time.now), 3)
    %w[One Two Three].each do |name|
      app.context.manager.create_event(Event.new(summary: name, date_start: day, date_end: day))
    end
    app.window.refresh_views
    cell = app.window.month_view.cells.flatten.find { |c| DateTimeUtils.compare_date(c.date, day).zero? }
    d.check('the cell has exactly the 3 events just created') { cell.events.length == 3 }
    d.check('3 fit with no overflow yet') { cell.overflow.zero? }
    d.check('so the overflow button stays hidden') { !cell.overflow_button.visible? }
  end

  d.step('a fourth event on that day pushes it into overflow') do
    day = DateTimeUtils.add_days(DateTimeUtils.start_of_day(Time.now), 3)
    app.context.manager.create_event(Event.new(summary: 'Four', date_start: day, date_end: day))
    app.window.refresh_views
    @overflow_cell = app.window.month_view.cells.flatten.find { |c| DateTimeUtils.compare_date(c.date, day).zero? }
    d.check('now there is an overflow of one') { @overflow_cell.overflow == 1 }
    d.check('the overflow button is visible') { @overflow_cell.overflow_button.visible? }
  end

  d.step('clicking the overflow button opens the month popover with all four') do
    @overflow_cell.overflow_button.activate
  end

  d.step('the month popover lists every event on that day') do
    wait_until { app.window.month_view.popover.popover.visible? }
    app.window.month_view.popover.then do |popover|
      d.check('it is showing') { popover.popover.visible? }
      d.check('the day label matches') { popover.date.day == @overflow_cell.date.day }
      d.shot('08-month-popover-overflow')
    end
  end

  d.step('the popover closes') do
    app.window.month_view.popover.close_button.activate
  end

  d.step('and it is gone') do
    wait_until { !app.window.month_view.popover.popover.visible? }
    d.check('it is gone') { !app.window.month_view.popover.popover.visible? }
  end

  # --- Calendar list: toggling visibility -----------------------------------

  d.step('toggling the calendar off in the sidebar hides its events') do
    row = app.window.calendar_list.listbox.get_row_at_index(0)
    app.window.calendar_list.listbox.signal_emit('row-activated', row)
    pump(50)
    d.check('the calendar is now hidden') { !app.context.manager.calendars.first.visible? }
    d.check('no events show in the range any more') do
      app.context.manager.events_in_range(app.window.month_view.range).empty?
    end
    d.shot('09-calendar-hidden')
  end

  d.step('toggling it back on restores the events') do
    row = app.window.calendar_list.listbox.get_row_at_index(0)
    app.window.calendar_list.listbox.signal_emit('row-activated', row)
    pump(50)
    d.check('visible again') { app.context.manager.calendars.first.visible? }
    d.check('events are back') { !app.context.manager.events_in_range(app.window.month_view.range).empty? }
  end

  # --- Menu, about, shortcuts ------------------------------------------------

  d.step("the header bar's menu carries upstream's three sections") do
    app.window.main_menu.then do |menu|
      d.check('three sections (sync, settings, about)') { menu.n_items == 3 }
      d.check('synchronize is in the first section') do
        menu.get_item_link(0, 'section').get_item_attribute_value(0, 'action', nil) == 'app.sync'
      end
      d.check('the settings section has two items') { menu.get_item_link(1, 'section').n_items == 2 }
      d.check('the about section has two items') { menu.get_item_link(2, 'section').n_items == 2 }
    end
  end

  d.step('app.sync refreshes and drives the sync indicator') do
    app.context.manager.on_synchronizing { |syncing| @saw_sync = true if syncing }
    app.app.lookup_action('sync').activate(nil)
    d.check('the synchronizing signal fired') { @saw_sync }
    d.check('the indicator shows success immediately after a synchronous refresh') do
      app.window.sync_indicator.stack.visible_child_name == 'success'
    end
    d.shot('10-sync-success')
    pump(SyncIndicator::SUCCESS_TIMEOUT + 300)
    d.check('and fades back to empty afterwards') { app.window.sync_indicator.stack.visible_child_name == 'empty' }
  end

  d.step('app.about presents the about dialog with upstream metadata') do
    app.app.lookup_action('about').activate(nil)
    d.check('it is showing') { app.window.window.visible_dialog.equal?(app.about_dialog) }
    d.check('the application name is Calendar') { app.about_dialog.application_name == 'Calendar' }
    d.check('the version is 1.0') { app.about_dialog.version == '1.0' }
    d.check("the website is upstream's") { app.about_dialog.website == App::UPSTREAM_URI }
    d.shot('11-about')
    app.window.window.visible_dialog&.close
  end

  d.step('app.shortcuts presents the shortcuts dialog') do
    app.app.lookup_action('shortcuts').activate(nil)
    d.check('it is showing') { app.window.window.visible_dialog.equal?(app.shortcuts_dialog.dialog) }
    d.shot('12-shortcuts')
    app.window.window.visible_dialog&.close
  end

  d.step('win.open-date-time-settings fails gracefully with no Settings app and toasts') do
    app.window.window.lookup_action('open-date-time-settings').activate(nil)
    d.check('a toast overlay exists to carry the message') { app.window.overlay.is_a?(Adwaita::ToastOverlay) }
  end

  # --- Accelerators and actions, read back rather than guessed --------------

  d.step("the window and app accelerators are upstream's, parsed to the same keyval") do
    Window::ACCELERATORS.each do |action, accels|
      d.check("#{action} is bound to #{accels.first}") do
        app.app.get_accels_for_action(action).map { |a| Gtk.accelerator_parse(a) } ==
          accels.map { |a| Gtk.accelerator_parse(a) }
      end
    end
    App::APP_ACCELERATORS.each do |action, accels|
      d.check("#{action} is bound to #{accels.first}") do
        app.app.get_accels_for_action(action).map { |a| Gtk.accelerator_parse(a) } ==
          accels.map { |a| Gtk.accelerator_parse(a) }
      end
    end
  end

  d.step('every window action named in ACCELERATORS actually exists') do
    %w[today next-date previous-date new-event open-date-time-settings open-online-accounts].each do |name|
      d.check("win.#{name} is installed") { !app.window.window.lookup_action(name).nil? }
    end
    d.check('win.change-view takes an int') do
      app.window.window.lookup_action('change-view').parameter_type.to_s.include?('i')
    end
  end

  # --- Breakpoints: upstream's responsive layout -----------------------------
  #
  # Firing 'apply'/'unapply' by hand does not work, on Adw.Breakpoint itself
  # and not just in the Ruby bindings: those two signals are what the
  # breakpoint *notifies with* once its own size-allocate watcher decides the
  # condition holds, not a trigger anything else can fire to make it decide
  # that — confirmed by reproducing it in a 6-line standalone script with no
  # driver involved at all: signal_emit('apply') returns, no setter moves,
  # and pumping 500ms of main-loop iterations afterwards changes nothing.
  # The only way to see a breakpoint actually fire is a window whose real
  # size crosses it, so this builds two more of this same app, pre-sized on
  # disk the way the main window's own startup size is seeded above, and
  # reads their real, GTK-decided layout.
  def narrow_app(width)
    dir = Dir.mktmpdir('gnome-calendar-narrow-config')
    config = File.join(dir, 'gnome-calendar-rb')
    FileUtils.mkdir_p(config)
    File.write(
      File.join(config, 'settings.json'),
      JSON.generate('window-width' => width, 'window-height' => 700, 'window-maximized' => false),
    )
    App.new(app_id: "org.gnome.CalendarRb.BreakpointCheck#{width}", context: Context.new(settings: Settings.new(path: File.join(config, 'settings.json'))))
  end

  d.step('a window narrower than 1000sp opens already collapsed') do
    @narrow_app = narrow_app(900)
    @narrow_app.window.build
    @narrow_app.window.present
  end

  d.step('it collapsed the sidebar and switched the switcher') do
    wait_until { @narrow_app.window.split_view.collapsed? }
    d.check('the split view collapsed') { @narrow_app.window.split_view.collapsed? }
    d.check('the narrow switcher is in the bin') do
      @narrow_app.window.view_switcher_bin.child.equal?(@narrow_app.window.view_switcher_narrow)
    end
    d.shot('13-collapsed-breakpoint', @narrow_app.window.window)
    @narrow_app.window.window.close
  end

  d.step('a window narrower than 700sp hides navigation entirely') do
    @narrower_app = narrow_app(600)
    @narrower_app.window.build
    @narrower_app.window.present
  end

  d.step('the switcher and navigation buttons are all hidden') do
    wait_until { !@narrower_app.window.view_switcher_bin.visible? }
    d.check('the switcher bin is hidden') { !@narrower_app.window.view_switcher_bin.visible? }
    d.check('previous/next are hidden') do
      !@narrower_app.window.previous_date_button.visible? && !@narrower_app.window.next_date_button.visible?
    end
    d.check('the sidebar button is hidden') { !@narrower_app.window.sidebar_button.visible? }
    d.shot('14-narrow-breakpoint', @narrower_app.window.window)
    @narrower_app.window.window.close
  end

  d.step('and the main window is unaffected by either') do
    d.check('the main window never collapsed') { !app.window.split_view.collapsed? }
    d.check('its switcher is still the wide one') do
      app.window.view_switcher_bin.child.equal?(app.window.view_switcher_wide)
    end
    d.check('its navigation is still showing') { app.window.previous_date_button.visible? }
  end

  # --- Date chooser (sidebar) and its MultiChoice controls -------------------

  d.step('opening the sidebar so its date chooser is mapped and clickable') do
    app.window.sidebar_button.active = true
    d.check('the sidebar is open') { app.window.split_view.show_sidebar? }
  end

  d.step("the sidebar date chooser's month stepper moves the active date") do
    @chooser_start_month = app.window.date_chooser.active_date.month
    app.window.date_chooser.month_choice.up_button.activate
  end

  d.step('it moved forward, and stepping back restores it') do
    wait_until { app.window.active_date.month == (@chooser_start_month % 12) + 1 }
    d.check("stepping the month moved the window's active date") do
      app.window.active_date.month == (@chooser_start_month % 12) + 1
    end
    app.window.date_chooser.month_choice.down_button.activate
  end

  d.step('it is back where it started') do
    wait_until { app.window.active_date.month == @chooser_start_month }
    d.check('stepping back restores it') { app.window.active_date.month == @chooser_start_month }
    d.shot('15-date-chooser')
  end

  d.step('clicking a day in the date chooser moves the active date there') do
    @chooser_target = app.window.date_chooser.days[1][2]
    @chooser_target.button.activate
  end

  d.step('the active date followed the click') do
    wait_until { DateTimeUtils.compare_date(app.window.active_date, @chooser_target.date).zero? }
    d.check('the active date followed the click') do
      DateTimeUtils.compare_date(app.window.active_date, @chooser_target.date).zero?
    end
    app.window.today_button.activate
  end

  d.step('closing the sidebar again') do
    app.window.sidebar_button.active = false
    d.check('the sidebar is closed') { !app.window.split_view.show_sidebar? }
  end

  # --- Model layer, exercised through the running app's own objects ---------

  d.step('Manager default/writable/visible calendar queries answer correctly') do
    manager = app.context.manager
    d.check('one calendar, and it is the default') { manager.default_calendar.equal?(manager.calendars.first) }
    d.check('it is writable') { manager.writable_calendars.include?(manager.default_calendar) }
    d.check('it is visible') { manager.visible_calendars.include?(manager.default_calendar) }
    d.check('calendar(id) finds it by id') do
      manager.calendar(manager.default_calendar.id).equal?(manager.default_calendar)
    end
  end

  d.step('creating a second calendar and moving an event into it') do
    manager = app.context.manager
    work = manager.create_calendar(name: 'Work', color: '#e01b24')
    d.check('two calendars now') { manager.calendars.length == 2 }
    standup = manager.events_in_range(app.window.month_view.range).find { |e| e.summary == 'Standup' }
    moved = manager.move_event_to_calendar(standup, work)
    d.check('the event followed') { moved.calendar.equal?(work) }
    d.check('it is on disk under the new calendar') { File.read(work.path).include?('Standup') }
    manager.remove_calendar(work)
    d.check('removing the calendar removes its events too') { manager.events_of(work).empty? }
    d.check('one calendar again') { manager.calendars.length == 1 }
  end

  d.step('Settings persists and round-trips through a fresh instance') do
    settings = app.context.settings
    settings.window_size = [800, 650]
    reloaded = Settings.new(path: settings.location)
    d.check('the size round-tripped') { reloaded.window_size == [800, 650] }
    d.check('active_view_index round-trips too') do
      reloaded.active_view_index = 2
      Settings.new(path: settings.location).active_view_index == 2
    end
  end

  d.step("CalendarRange overlap and contains? agree with upstream's cases") do
    day = DateTimeUtils.start_of_day(Time.now)
    whole_day = CalendarRange.new(day, DateTimeUtils.add_days(day, 1))
    morning = CalendarRange.new(day, DateTimeUtils.add_days(day, 0) + (3600 * 6))
    d.check('the morning is a subset of the whole day') { morning.overlap(whole_day).first == CalendarRange::SUBSET }
    d.check('and the whole day is its superset') { whole_day.overlap(morning).first == CalendarRange::SUPERSET }
    d.check('the day contains its own midnight') { whole_day.contains?(day) }
    d.check("the day does not contain the next day's midnight (half-open)") do
      !whole_day.contains?(DateTimeUtils.add_days(day, 1))
    end
  end

  d.step('RangeTree finds and removes what was added') do
    tree = RangeTree.new
    day = DateTimeUtils.start_of_day(Time.now)
    range = CalendarRange.new(day, DateTimeUtils.add_days(day, 1))
    tree.add_range(range, :marker)
    d.check('one entry is found at that range') { tree.count_entries_at_range(range) == 1 }
    tree.remove_data(:marker)
    d.check('removing it empties the tree') { tree.empty? }
  end

  d.step("Utils helpers answer upstream's values") do
    d.check('month_name(0) is January') { Utils.month_name(0) == 'January' }
    d.check('weekday(0) is Sun') { Utils.weekday(0) == 'Sun' }
    d.check('grid_weekday(0) is S') { Utils.grid_weekday(0) == 'S' }
    d.check('valid_event_name? rejects blank') { !Utils.valid_event_name?('   ') }
    d.check('valid_event_name? accepts text') { Utils.valid_event_name?('x') }
    d.check('extract_meeting_url finds nothing in plain text') { Utils.extract_meeting_url('hello').last.nil? }
    description = "Join\n#{Utils::GOOGLE_DELIMITER}\nhttps://meet.google.com/abc-defg-hij\n#{Utils::GOOGLE_DELIMITER}\n"
    d.check('extract_meeting_url finds a Google Meet link') do
      Utils.extract_meeting_url(description).last == 'https://meet.google.com/abc-defg-hij'
    end
  end

  d.step("Event comparisons and formatting follow upstream's rules") do
    morning = Event.new(
      summary:    'AM',
      date_start: Time.new(2026, 1, 1, 9, 0, 0),
      date_end:   Time.new(2026, 1, 1, 10, 0, 0),
    )
    afternoon = Event.new(
      summary:    'PM',
      date_start: Time.new(2026, 1, 1, 14, 0, 0),
      date_end:   Time.new(2026, 1, 1, 15, 0, 0),
    )
    all_day = Event.new(
      summary:    'Holiday',
      all_day:    true,
      date_start: Time.new(2026, 1, 1),
      date_end:   Time.new(2026, 1, 2),
    )
    d.check('all-day sorts before timed') { all_day.compare(morning).negative? }
    d.check('morning sorts before afternoon') { morning.compare(afternoon).negative? }
    d.check('a timed event is not multiday') { !morning.multiday? }
    d.check('format_date for a timed event names both times') { morning.format_date.include?('–') }
    d.check('round-trips through to_h/from_h') { Event.from_h(morning.to_h).summary == 'AM' }
  end

  # --- Shutdown -------------------------------------------------------------

  d.step('the window is still the only toplevel at the end of the run') do
    d.check('only the one toplevel is up') { Gtk::Window.list_toplevels.length == 1 }
  end
end
