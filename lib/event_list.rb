# frozen_string_literal: true

require_relative 'event'

# EventList is an observable list of events. Upstream makes it a GListModel so
# a GtkListView can watch it; the port keeps the same add/remove API and
# notifies its watchers, which is what the views rebuild from.
#
# Events are held in upstream's sort order (all-day first, then by start, then
# longest first), so a view can render the list as it comes.
#
# Ported from upstream's src/core/gcal-event-list.c.
#
class EventList
  include Enumerable

  def initialize(events = [])
    @events = []
    @handlers = []
    add_events(events)
  end

  # Upstream's GListModel "items-changed": the block is called after every
  # change, with the list itself.
  def on_changed(&block)
    @handlers << block
    block
  end

  def each(&) = @events.each(&)

  def length = @events.length

  def empty? = @events.empty?

  def [](index) = @events[index]

  def to_a = @events.dup

  # Upstream's gcal_event_list_add_event(). Adding an event already in the
  # list replaces it, so an update does not double it up.
  def add_event(event)
    index = @events.index { |existing| existing.uuid == event.uuid }
    unless index.nil?
      @events.delete_at(index)
    end
    @events << event
    sort_and_notify
    event
  end

  # Upstream's gcal_event_list_add_events(): one notification for the batch.
  def add_events(events)
    events.each do |event|
      @events.reject! { |existing| existing.uuid == event.uuid }
      @events << event
    end
    sort_and_notify
    self
  end

  # Upstream's gcal_event_list_remove_event().
  def remove_event(event)
    @events.reject! { |existing| existing.uuid == event.uuid }
    sort_and_notify
    self
  end

  # Upstream's gcal_event_list_remove_events().
  def remove_events(events)
    uuids = events.map(&:uuid)
    @events.reject! { |existing| uuids.include?(existing.uuid) }
    sort_and_notify
    self
  end

  # Upstream's gcal_event_list_remove_all_events().
  def remove_all_events
    @events = []
    sort_and_notify
    self
  end

  # Replaces the whole list in one go, which is what a view does when the
  # date it shows changes.
  def replace(events)
    @events = []
    add_events(events)
  end

  private

    def sort_and_notify
      @events.sort! { |first, second| first.compare(second) }
      @handlers.each { |handler| handler.call(self) }
      self
    end
end
