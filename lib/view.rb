# frozen_string_literal: true

require_relative 'date_time_utils'

# View is what the window expects of anything it puts in its view stack: an
# active date it can move forwards and backwards, the direction time runs in
# so the navigation buttons can point the right way, and the three signals a
# view raises — create an event here, create one and open the editor, and this
# event was activated.
#
# Upstream declares this as a GInterface with default signal handlers; the
# port makes it a module the views include, which gives them the same shared
# signal plumbing without repeating it three times.
#
# Ported from upstream's src/gui/views/gcal-view.c and
# src/gui/views/gcal-view.h.
#
module View
  # Upstream's "create-event" signal: a range, and where in the view the
  # click landed.
  def on_create_event(&block)
    create_event_handlers << block
    block
  end

  # Upstream's "create-event-detailed" signal: a range, no coordinates,
  # straight into the editor.
  def on_create_event_detailed(&block)
    create_event_detailed_handlers << block
    block
  end

  # Upstream's "event-activated" signal.
  def on_event_activated(&block)
    event_activated_handlers << block
    block
  end

  def emit_create_event(range, x, y)
    create_event_handlers.each { |handler| handler.call(range, x, y) }
    self
  end

  def emit_create_event_detailed(range)
    create_event_detailed_handlers.each { |handler| handler.call(range) }
    self
  end

  def emit_event_activated(event, widget)
    event_activated_handlers.each { |handler| handler.call(event, widget) }
    self
  end

  def create_event_handlers = @create_event_handlers ||= []

  def create_event_detailed_handlers = @create_event_detailed_handlers ||= []

  def event_activated_handlers = @event_activated_handlers ||= []

  # Upstream's gcal_view_get_time_direction(): vertical for the week view,
  # horizontal for the month and agenda views. Each view overrides it.
  def time_direction = :horizontal

  # Upstream's gcal_view_clear_marks(). A view with nothing to unmark
  # inherits this no-op, as upstream's views that implement it trivially do.
  def clear_marks = self

  # Upstream's gcal_view_get_children_by_uuid().
  def children_by_uuid(_mod, _uuid) = []
end
