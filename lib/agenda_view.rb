# frozen_string_literal: true

require 'adwaita'
require_relative 'agenda_view_day'
require_relative 'agenda_view_day_row'
require_relative 'date_chooser'
require_relative 'date_time_utils'
require_relative 'range'
require_relative 'utils'
require_relative 'view'

# AgendaView is the narrow-window view: a month chooser at the top, then a
# day-by-day list starting at the active date.
#
# A day with nothing on it is hidden unless it is the active date, which keeps
# the list from being mostly blank — upstream's
# n_items_and_date_to_boolean() filter.
#
# Stepping forwards and backwards moves one day at a time, which is why the
# window labels its buttons "Yesterday" and "Tomorrow" in this view.
#
# Ported from upstream's src/gui/views/gcal-agenda-view.blp and
# src/gui/views/gcal-agenda-view.c.
#
class AgendaView
  include View

  DAYS = Utils::N_WEEKDAYS

  attr_reader :active_date

  def initialize(context)
    @context = context
    @active_date = DateTimeUtils.start_of_day(Time.now)
    @events = []
    @attached = []
  end

  def build
    root_box.tap do |root|
      root.append(date_chooser.build)
      root.append(scrolled_window)

      scrolled_window.tap do |scroller|
        scroller.child = list_box
      end

      day_rows.each(&:build)

      day_rows.each do |row|
        row.on_event_activated { |event, widget| emit_event_activated(event, widget) }
      end

      date_chooser.tap do |chooser|
        chooser.on_day_selected { |date| self.active_date = date }
      end

      refresh
    end
  end

  def widget = build

  # Upstream's GcalView::time-direction for the agenda view.
  def time_direction = :horizontal

  # Upstream's gcal_agenda_view_set_date(): each day object moves to the
  # next date along.
  def active_date=(date)
    @active_date = DateTimeUtils.start_of_day(date)
    date_chooser.active_date = @active_date
    days.each_with_index { |day, index| day.date = DateTimeUtils.add_days(@active_date, index) }
    refresh
    @active_date
  end

  def next_date = DateTimeUtils.add_days(@active_date, 1)

  def previous_date = DateTimeUtils.add_days(@active_date, -1)

  # Upstream's gcal_agenda_view_get_range(): from the active date to the end
  # of its week.
  def range
    CalendarRange.new(@active_date, DateTimeUtils.end_of_week(@active_date), CalendarRange::DEFAULT)
  end

  def refresh
    @events = @context.manager.events_in_range(whole_range)
    days.each { |day| day.events_from(@events) }
    date_chooser.events = @context.manager.events_in_range(date_chooser_range)
    apply_filter
    self
  end

  # The day rows currently in the list — what the agenda is actually
  # showing, once the filter below has had its say.
  def visible_day_rows = @attached.dup

  def children_by_uuid(_mod, uuid) = @events.select { |event| event.uuid == uuid }

  def root_box
    @root_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.add_css_class('agenda-view')
    end
  end

  def date_chooser
    @date_chooser ||= DateChooser.new(
      active_date:        @active_date,
      split_month_year:   false,
      show_selected_week: true,
    )
  end

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scroller|
      scroller.hexpand = true
      scroller.vexpand = true
      scroller.hscrollbar_policy = :never
    end
  end

  def list_box
    @list_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.vexpand = true
    end
  end

  def days
    @days ||= Array.new(DAYS) do |index|
      AgendaViewDay.new(date: DateTimeUtils.add_days(@active_date, index))
    end
  end

  def day_rows
    @day_rows ||= days.map { |day| AgendaViewDayRow.new(day, time_format: @context.time_format) }
  end

  private

    # The days are always a week long, so the events are fetched for the
    # whole week even when the view's own range stops at its end.
    def whole_range
      CalendarRange.new(
        @active_date,
        DateTimeUtils.add_days(@active_date, DAYS),
        CalendarRange::DEFAULT,
      )
    end

    # The month the chooser is showing, which is what it needs to draw dots.
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
        DateTimeUtils.add_days(first, -DAYS),
        DateTimeUtils.add_days(first, 42 + DAYS),
        CalendarRange::DEFAULT,
      )
    end

    # Upstream's n_items_and_date_to_boolean(): a day shows when it is
    # inside the view's range and either has events or is the active date.
    # Upstream drops the others from a FilterListModel, so the port takes
    # their rows out of the list rather than hiding them in place.
    def apply_filter
      view_range = range
      wanted = days.each_index.select { |index| day_visible?(view_range, days[index]) }

      @attached.each { |row| list_box.remove(row.bin) }
      @attached = wanted.map { |index| day_rows[index] }
      @attached.each { |row| list_box.append(row.bin) }
      self
    end

    def day_visible?(view_range, day)
      view_range.contains?(day.date) &&
        (day.n_items.positive? || DateTimeUtils.compare_date(day.date, @active_date).zero?)
    end

end
