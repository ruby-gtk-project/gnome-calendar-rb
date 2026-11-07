# frozen_string_literal: true

require 'adwaita'
require_relative 'event_widget'
require_relative 'settings'

# EventWidgetPool is a pool of EventWidgets. The views rebuild their visible
# event widgets often — every scroll, every navigation, every refresh from
# the manager — and building one from scratch is comparatively expensive, so
# a pool keeps spare widgets around and hands them back out rather than
# forcing every rebuild to construct new ones from nothing.
#
# The pool is shared from Context, one per application, exactly as upstream's
# single GcalEventWidgetPool is shared from GcalWindow.
#
# Ported from upstream's src/gui/gcal-event-widget-pool.c.
#
class EventWidgetPool
  # Upstream preallocates 600 widgets at startup, a number sized for GTK's
  # template instantiation cost in C. Building a GtkButton from Ruby is not
  # free either, but startup latency matters more than it does upstream, so
  # the port preallocates a much smaller number and grows the pool lazily
  # from take_or_create instead.
  N_PREALLOCATED_EVENT_WIDGETS = 16

  def initialize(preallocate: N_PREALLOCATED_EVENT_WIDGETS, time_format: Settings::FORMAT_24H)
    @time_format = time_format
    @pool = Array.new(preallocate) { EventWidget.new(nil, time_format: @time_format).tap(&:build) }
  end

  # Upstream's gcal_event_widget_pool_take_or_create(): an event widget bound
  # to @event, taken from the pool when it has one spare, built fresh
  # otherwise.
  def take_or_create(event, time_format: @time_format)
    event_widget = @pool.pop || EventWidget.new(event, time_format: time_format).tap(&:build)
    event_widget.time_format = time_format
    event_widget.event = event
    event_widget
  end

  # Upstream's gcal_event_widget_pool_reclaim(): resets @event_widget and
  # stores it for later reuse. The caller must have already removed it from
  # its parent container.
  def reclaim(event_widget)
    event_widget.button.visible = true
    event_widget.event = nil
    @pool.push(event_widget)
    self
  end

  def size = @pool.size
end
