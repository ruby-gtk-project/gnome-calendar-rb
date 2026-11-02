# frozen_string_literal: true

require 'adwaita'
require_relative 'date_time_utils'
require_relative 'event'
require_relative 'range'
require_relative 'utils'

# QuickAddPopover is what a click on an empty day opens: a heading naming the
# day, a title entry, the list of calendars the event could go in, and a Save
# button.
#
# The heading is upstream's: "New Event Today", "New Event next Tuesday",
# "New Event on March 14", or "New Event from … to …" for a range covering
# more than a day.
#
# Ported from upstream's src/gui/gcal-quick-add-popover.blp and
# src/gui/gcal-quick-add-popover.c.
#
class QuickAddPopover
  COLOR_SIZE = 16

  attr_reader :range

  def initialize(context)
    @context = context
    @range = nil
    @selected_calendar = nil
    @rows = {}
    @parent = nil
    @create_handlers = []
  end

  # Assembles the widget tree once; a second call is a no-op, which is what
  # lets a caller ask for the built popover without caring whether it already
  # exists.
  def build
    unless @assembled
      @assembled = assemble
    end
    popover
  end

  def assemble
    popover.tap do |widget|
      widget.child = box

      box.tap do |container|
        container.append(title_label)
        container.append(summary_list)
        container.append(scrolled_window)
        container.append(button_box)

        summary_list.tap do |list|
          list.append(summary_entry)
        end

        scrolled_window.tap do |scroller|
          scroller.child = calendars_list_box
        end

        button_box.tap do |buttons|
          buttons.append(add_button)
        end
      end

      summary_entry.tap do |entry|
        entry.signal_connect('notify::text') { update_sensitivity }
        entry.signal_connect('entry-activated') { create_event }
      end

      calendars_list_box.tap do |list|
        list.signal_connect('row-selected') { |_list, row| select_row(row) }
      end

      add_button.tap do |button|
        button.signal_connect('clicked') { create_event }
      end

      widget.signal_connect('show') { summary_entry.grab_focus }
    end
  end

  def widget = build

  # Emitted once the event has been created, so the view can refresh.
  def on_event_created(&block)
    @create_handlers << block
    block
  end

  # Upstream's gcal_quick_add_popover_set_date_range(): the range the new
  # event will cover, which also writes the heading.
  def show_for(range, parent)
    @range = range
    summary_entry.text = ''
    title_label.text = header_string
    rebuild_calendar_rows
    update_sensitivity
    unless @parent == parent
      @parent = parent
      popover.set_parent(parent)
    end
    popover.popup
    self
  end

  def popover
    @popover ||= Gtk::Popover.new.tap do |widget|
      widget.width_request = 360
      widget.add_css_class('quick-add-popover')
    end
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 12).tap do |container|
      container.margin_top = 12
      container.margin_bottom = 12
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.hexpand = true
      label.wrap = true
      label.max_width_chars = 25
      label.xalign = 0.0
      label.margin_top = 6
      label.margin_bottom = 6
      label.margin_start = 27
      label.margin_end = 27
      label.add_css_class('title-4')
    end
  end

  def summary_list
    @summary_list ||= Gtk::ListBox.new.tap do |list|
      list.selection_mode = :none
      list.margin_start = 12
      list.margin_end = 12
      list.add_css_class('boxed-list')
    end
  end

  def summary_entry
    @summary_entry ||= Adwaita::EntryRow.new.tap do |entry|
      entry.title = 'Title'
    end
  end

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scroller|
      scroller.propagate_natural_height = true
      scroller.max_content_height = 240
    end
  end

  def calendars_list_box
    @calendars_list_box ||= Gtk::ListBox.new.tap do |list|
      list.margin_start = 12
      list.margin_end = 12
      list.margin_top = 12
      list.margin_bottom = 12
      list.add_css_class('boxed-list')
      list.add_css_class('calendars-list')
      list.add_css_class('compact')
    end
  end

  def button_box
    @button_box ||= Gtk::Box.new(:horizontal, 9).tap do |container|
      container.homogeneous = true
      container.margin_start = 12
      container.margin_end = 12
    end
  end

  def add_button
    @add_button ||= Gtk::Button.new(label: 'Save Event').tap do |button|
      button.valign = :center
      button.sensitive = false
      button.use_underline = true
      button.add_css_class('suggested-action')
    end
  end

  private

    def manager = @context.manager

    # Upstream's update_header(): a single day names the day, a longer range
    # names both ends.
    def header_string
      days = DateTimeUtils.compare_date(@range.range_end, @range.range_start)
      case days
      when ..1 then single_day_string(@range.range_start)
      else "New Event #{range_end_string(@range.range_start, 'from')} #{range_end_string(last_day, 'to')}"
      end
    end

    # The range is half-open, so its last day is the day before its end.
    def last_day = DateTimeUtils.add_days(@range.range_end, -1)

    # Upstream's get_date_string_for_day().
    def single_day_string(day)
      offset = DateTimeUtils.compare_date(Time.now, day)
      case offset
      when 0 then 'New Event Today'
      when -1 then 'New Event Tomorrow'
      when 1 then 'New Event Yesterday'
      when -7..-2 then "New Event next #{day.strftime('%A')}"
      else "New Event on #{Utils.month_name(day.month - 1)} #{day.day}"
      end
    end

    # Upstream's start/end halves of the multiday heading.
    def range_end_string(day, preposition)
      offset = DateTimeUtils.compare_date(Time.now, day)
      case offset
      when 0 then "#{preposition} Today"
      when -1 then "#{preposition} Tomorrow"
      when 1 then "#{preposition} Yesterday"
      when -7..-2 then "#{preposition} next #{day.strftime('%A')}"
      else "#{preposition} #{Utils.month_name(day.month - 1)} #{day.day}"
      end
    end

    # One row per writable calendar, the default one selected.
    def rebuild_calendar_rows
      @rows.each_key { |row| calendars_list_box.remove(row) }
      @rows = {}

      manager.writable_calendars.each do |calendar|
        row = build_calendar_row(calendar)
        @rows[row] = calendar
        calendars_list_box.append(row)
      end

      default_row = @rows.key(manager.default_calendar)
      unless default_row.nil?
        calendars_list_box.select_row(default_row)
      end
      self
    end

    def build_calendar_row(calendar)
      Adwaita::ActionRow.new.tap do |row|
        row.title = calendar.name
        row.activatable = true
        row.add_prefix(
          Gtk::Image.new.tap do |icon|
            icon.paintable = Utils.circle_paintable_from_color(calendar.color, COLOR_SIZE)
            icon.add_css_class('calendar-color-image')
          end,
        )
      end
    end

    def select_row(row)
      @selected_calendar = @rows[row]
      update_sensitivity
      @selected_calendar
    end

    # Upstream's summary_entry_text_changed(): Save stays insensitive until
    # the event has a name and somewhere to go.
    def update_sensitivity
      add_button.sensitive = Utils.valid_event_name?(summary_entry.text) && !target_calendar.nil?
      add_button.sensitive?
    end

    def target_calendar = @selected_calendar || manager.default_calendar

    # Upstream's edit_or_create_event() in its create half.
    def create_event
      if add_button.sensitive?
        event = Event.new(
          calendar:   target_calendar,
          summary:    summary_entry.text.strip,
          all_day:    @range.date_only? || DateTimeUtils.date?(@range.range_start),
          date_start: @range.range_start,
          date_end:   @range.range_end,
        )
        manager.create_event(event)
        popover.popdown
        @create_handlers.each { |handler| handler.call(event) }
      end
      self
    end
end
