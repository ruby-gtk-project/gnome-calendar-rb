# frozen_string_literal: true

require 'adwaita'
require_relative 'utils'

# CalendarList is the sidebar's list of calendars: a colour dot, the name, and
# a checkmark when the calendar is shown. Activating a row toggles whether its
# events appear in the views.
#
# Upstream binds the list box to the manager's calendars model; the port
# rebuilds the rows whenever the manager says a calendar was added, changed or
# removed, which the manager signals for exactly those three cases.
#
# Ported from upstream's src/gui/gcal-calendar-list.blp and
# src/gui/gcal-calendar-list.c.
#
class CalendarList
  COLOR_SIZE = 16

  def initialize(context)
    @context = context
    @rows = {}
    @calendars_by_row = {}
  end

  def build
    bin.tap do |root|
      root.child = scrolled_window

      scrolled_window.tap do |scroller|
        scroller.child = clamp

        clamp.tap do |container|
          container.child = listbox
        end
      end

      listbox.tap do |list|
        list.signal_connect('row-activated') { |_list, row| toggle_row(row) }
      end

      manager.on_calendar_added { refresh }
      manager.on_calendar_changed { refresh }
      manager.on_calendar_removed { refresh }

      refresh
    end
  end

  def widget = build

  # Rebuilds every row from the manager's calendars, in name order.
  def refresh
    @rows.each_value { |row| listbox.remove(row) }
    @rows = {}
    @calendars_by_row = {}

    manager.calendars.sort_by { |calendar| calendar.name.downcase }.each do |calendar|
      row = build_row(calendar)
      @rows[calendar.id] = row
      listbox.append(row)
    end
    self
  end

  def bin = @bin ||= Adwaita::Bin.new.tap { |widget| widget.add_css_class('calendar-list') }

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scroller|
      scroller.hscrollbar_policy = :never
      scroller.propagate_natural_height = true
      scroller.propagate_natural_width = true
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |container|
      container.maximum_size = 800
      container.tightening_threshold = 800
    end
  end

  def listbox
    @listbox ||= Gtk::ListBox.new.tap do |list|
      list.hexpand = true
      list.selection_mode = :none
      list.add_css_class('navigation-sidebar')
    end
  end

  private

    def manager = @context.manager

    # Upstream's create_row_func(): the colour dot, the name, and the
    # checkmark that tracks the calendar's visibility.
    def build_row(calendar)
      Gtk::ListBoxRow.new.tap do |row|
        row.accessible_role = :checkbox
        row.child = Gtk::Box.new(:horizontal, 12).tap do |box|
          box.margin_start = 6
          box.margin_end = 6
          box.append(color_icon(calendar))
          box.append(name_label(calendar))
          box.append(check_image(calendar))
        end
        @calendars_by_row[row] = calendar
      end
    end

    def color_icon(calendar)
      Gtk::Image.new.tap do |icon|
        icon.paintable = Utils.circle_paintable_from_color(calendar.color, COLOR_SIZE)
        icon.add_css_class('calendar-color-image')
      end
    end

    def name_label(calendar)
      Gtk::Label.new(calendar.name).tap do |label|
        label.xalign = 0.0
        label.ellipsize = :end
        label.hexpand = true
        label.tooltip_text = calendar.name
      end
    end

    def check_image(calendar)
      Gtk::Image.new(icon_name: 'checkmark-small-symbolic').tap do |image|
        image.visible = calendar.visible?
      end
    end

    # Upstream's on_listbox_row_activated_cb().
    def toggle_row(row)
      calendar = @calendars_by_row[row]
      unless calendar.nil?
        manager.set_calendar_visible(calendar, !calendar.visible?)
      end
      self
    end
end
