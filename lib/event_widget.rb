# frozen_string_literal: true

require 'adwaita'
require_relative 'settings'
require_relative 'style'

# EventWidget is one event as it appears inside a view: a coloured edge, the
# summary, and the start time. It comes in two layouts, as upstream's does —
# summary and time side by side when there is room, stacked when the widget is
# taller than it is wide (the week grid).
#
# The colour is the event's, applied through a generated style class so the
# edge and the tinted background both follow it (see Style.color_class).
#
# Ported from upstream's src/gui/gcal-event-widget.blp and
# src/gui/gcal-event-widget.c.
#
class EventWidget
  HORIZONTAL = :horizontal
  VERTICAL = :vertical

  attr_reader :event

  def initialize(event, time_format: Settings::FORMAT_24H, layout: HORIZONTAL)
    @event = event
    @time_format = time_format
    @layout = layout
    @activate_handlers = []
    @color_class = nil
  end

  def build
    button.tap do |widget|
      widget.child = content_box

      content_box.tap do |container|
        container.append(edge)
        container.append(body)
      end

      body.tap do |container|
        case @layout
        when VERTICAL
          container.append(timestamp_label)
          container.append(summary_inscription)
        else
          container.append(summary_inscription)
          container.append(timestamp_label)
        end
      end

      widget.signal_connect('clicked') do
        @activate_handlers.each { |handler| handler.call(@event, self) }
      end

      refresh
    end
  end

  def widget = build

  # Upstream's "activate" signal, raised by a click on the event.
  def on_activated(&block)
    @activate_handlers << block
    block
  end

  # Rebuilds the text and the colour from the event, which is what an update
  # from the manager triggers.
  def refresh
    summary_inscription.text = @event.summary
    summary_inscription.tooltip_text = @event.format_date(@time_format)
    timestamp_label.text = @event.format_timestamp(@time_format)
    timestamp_label.visible = !@event.all_day?
    apply_color
    self
  end

  def time_format=(time_format)
    @time_format = time_format
    refresh
    time_format
  end

  # Upstream's slanted classes: an event continuing past the edge of the
  # view loses the rounding on that side.
  def slanted_start=(slanted)
    apply_class('slanted-start', slanted)
    slanted
  end

  def slanted_end=(slanted)
    apply_class('slanted-end', slanted)
    slanted
  end

  def button
    @button ||= Gtk::Button.new.tap do |widget|
      widget.hexpand = true
      widget.add_css_class(Style::EVENT)
      widget.add_css_class('flat')
      widget.has_frame = false
    end
  end

  def content_box = @content_box ||= Gtk::Box.new(:horizontal, 0)

  def edge
    @edge ||= Adwaita::Bin.new.tap do |bin|
      bin.add_css_class('edge')
      bin.width_request = 6
    end
  end

  def body
    @body ||= Gtk::Box.new(body_orientation, body_spacing).tap do |container|
      container.hexpand = true
      container.add_css_class('content')
    end
  end

  def summary_inscription
    @summary_inscription ||= Gtk::Inscription.new.tap do |widget|
      widget.hexpand = true
      widget.xalign = 0.0
      widget.yalign = 0.5
      widget.min_lines = 1
      widget.text_overflow = :ellipsize_end
    end
  end

  def timestamp_label
    @timestamp_label ||= Gtk::Label.new.tap do |widget|
      widget.halign = :end
      widget.add_css_class('dimmed')
    end
  end

  private

    def body_orientation
      case @layout
      when VERTICAL then :vertical
      else :horizontal
      end
    end

    def body_spacing
      case @layout
      when VERTICAL then 0
      else 4
      end
    end

    # Swaps the generated colour class when the event's colour changes.
    def apply_color
      new_class = Style.color_class(@event.color)
      unless new_class == @color_class
        unless @color_class.nil?
          button.remove_css_class(@color_class)
        end
        button.add_css_class(new_class)
        @color_class = new_class
      end
      @color_class
    end

    def apply_class(name, present)
      if present
        button.add_css_class(name)
      else
        button.remove_css_class(name)
      end
      present
    end
end
