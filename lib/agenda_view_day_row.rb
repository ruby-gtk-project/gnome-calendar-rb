# frozen_string_literal: true

require 'adwaita'
require_relative 'agenda_view_day'
require_relative 'date_time_utils'
require_relative 'event_widget'
require_relative 'event_widget_pool'
require_relative 'settings'
require_relative 'style'

# AgendaViewDayRow is one day's block in the agenda: a heading naming the day,
# and a list of that day's events — or an italic "No events" when there are
# none.
#
# The heading says "Today", "Tomorrow" or "Yesterday" for those three days and
# names the day otherwise, which is upstream's new_date_header_string().
#
# Ported from upstream's src/gui/views/gcal-agenda-view-day-row.blp and
# src/gui/views/gcal-agenda-view-day-row.c.
#
class AgendaViewDayRow
  attr_reader :day

  def initialize(day, time_format: Settings::FORMAT_24H, event_widget_pool: nil)
    @day = day
    @time_format = time_format
    @event_widget_pool = event_widget_pool || EventWidgetPool.new(time_format: time_format)
    @rows = []
    @event_widgets = []
    @handlers = []
  end

  def build
    bin.tap do |root|
      root.child = box

      box.tap do |container|
        container.append(title_label)
        container.append(listbox)
      end

      listbox.tap do |list|
        list.set_placeholder(placeholder_label)
      end

      day.on_changed { refresh }
      refresh
    end
  end

  def widget = build

  def on_event_activated(&block)
    @handlers << block
    block
  end

  def time_format=(time_format)
    @time_format = time_format
    refresh
    time_format
  end

  def refresh
    title_label.text = header_string(day.date)
    rebuild_rows
    self
  end

  def bin
    @bin ||= Adwaita::Bin.new.tap { |widget| widget.add_css_class(Style::AGENDA_DAY_ROW) }
  end

  def box = @box ||= Gtk::Box.new(:vertical, 0)

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.xalign = 0.0
      label.add_css_class('caption-heading')
    end
  end

  def listbox
    @listbox ||= Gtk::ListBox.new.tap do |list|
      list.hexpand = true
      list.vexpand = true
      list.selection_mode = :none
    end
  end

  def placeholder_label
    @placeholder_label ||= Gtk::Label.new('No events').tap do |label|
      label.xalign = 0
      label.add_css_class('no-events')
      label.add_css_class('dimmed')
    end
  end

  private

    # Upstream's new_date_header_string().
    def header_string(date)
      today = Time.now
      if DateTimeUtils.compare_date(date, today).zero?
        'Today'
      elsif DateTimeUtils.compare_date(date, DateTimeUtils.add_days(today, 1)).zero?
        'Tomorrow'
      elsif DateTimeUtils.compare_date(date, DateTimeUtils.add_days(today, -1)).zero?
        'Yesterday'
      else
        date.strftime('%A %B %d')
      end
    end

    def rebuild_rows
      @rows.each { |row| row.child = nil }
      @rows.each { |row| listbox.remove(row) }
      @event_widgets.each { |event_widget| @event_widget_pool.reclaim(event_widget) }
      @event_widgets = []
      @rows = day.events.map { |event| build_row(event) }
      @rows.each { |row| listbox.append(row) }
      self
    end

    def build_row(event)
      event_widget = @event_widget_pool.take_or_create(event, time_format: @time_format).tap do |widget|
        widget.on_activated do |activated, inner|
          @handlers.each { |handler| handler.call(activated, inner) }
        end
      end
      @event_widgets << event_widget

      Gtk::ListBoxRow.new.tap do |row|
        row.activatable = false
        row.child = event_widget.button
      end
    end
end
