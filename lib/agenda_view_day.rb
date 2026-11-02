# frozen_string_literal: true

require_relative 'date_time_utils'
require_relative 'range'

# AgendaViewDay is one day in the agenda: the date, and the events that fall
# on it. It exists so the agenda can hand its rows a stable object per day
# rather than re-slicing the event list every time one of them redraws.
#
# Ported from upstream's src/gui/views/gcal-agenda-view-day.c and
# src/gui/views/gcal-agenda-view-day.h.
#
class AgendaViewDay
  attr_reader :date, :events

  def initialize(date: nil)
    @date = date || DateTimeUtils.start_of_day(Time.now)
    @events = []
    @handlers = []
  end

  # Upstream's "items-changed" on the day's model.
  def on_changed(&block)
    @handlers << block
    block
  end

  # Upstream's gcal_agenda_view_day_set_date().
  def date=(value)
    @date = DateTimeUtils.start_of_day(value)
    notify
    @date
  end

  # Upstream's gcal_agenda_view_day_set_model(): the day picks its own
  # events out of the view's list.
  def events_from(events)
    @events = events.select { |event| event.overlaps?(range) }
                    .sort { |first, second| first.compare(second) }
    notify
    @events
  end

  # Upstream's n-items property, which the agenda's filter reads.
  def n_items = @events.length

  def range = CalendarRange.new(@date, DateTimeUtils.add_days(@date, 1), CalendarRange::DEFAULT)

  private

    def notify
      @handlers.each { |handler| handler.call(self) }
      self
    end
end
