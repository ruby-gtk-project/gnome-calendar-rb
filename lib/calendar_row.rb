# frozen_string_literal: true

require 'adwaita'
require_relative 'utils'

# CalendarRow is one calendar in a list: its colour as a filled circle, its
# name, and a crossed-out eye when it is hidden. Rows can carry suffix
# widgets, which is how the calendar management pages hang a "read only" tag
# or an edit button off them.
#
# Ported from upstream's src/gui/common/gcal-calendar-row.blp and
# src/gui/common/gcal-calendar-row.c.
#
class CalendarRow
  COLOR_SIZE = 16

  attr_reader :calendar

  def initialize(calendar)
    @calendar = calendar
  end

  def build
    row.tap do |widget|
      widget.child = header_box

      header_box.tap do |container|
        container.append(color_image)
        container.append(title_label)
        container.append(end_box)

        end_box.tap do |box|
          box.append(visibility_image)
          box.append(suffix)
        end
      end

      refresh
    end
  end

  def widget = build

  # Upstream's gcal_calendar_row_add_suffix().
  def add_suffix(child)
    suffix.visible = true
    suffix.append(child)
    child
  end

  def first_suffix_child = suffix.first_child

  # Pulls the colour, the name and the visibility off the calendar again.
  def refresh
    color_image.paintable = Utils.circle_paintable_from_color(calendar.color, COLOR_SIZE)
    title_label.text = calendar.name
    title_label.tooltip_text = calendar.name
    visibility_image.visible = !calendar.visible?
    self
  end

  def row
    @row ||= Adwaita::PreferencesRow.new.tap do |widget|
      widget.title = calendar.name
      widget.activatable = false
    end
  end

  def header_box
    @header_box ||= Gtk::Box.new(:horizontal, 6).tap do |container|
      container.add_css_class('header')
    end
  end

  def color_image
    @color_image ||= Gtk::Image.new.tap do |widget|
      widget.accessible_role = :presentation
      widget.add_css_class('calendar-color-image')
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |widget|
      widget.ellipsize = :end
      widget.xalign = 0.0
    end
  end

  def end_box
    @end_box ||= Gtk::Box.new(:horizontal, 6).tap do |container|
      container.halign = :end
      container.hexpand = true
    end
  end

  def visibility_image
    @visibility_image ||= Gtk::Image.new(icon_name: 'eye-not-looking-symbolic')
  end

  def suffix
    @suffix ||= Gtk::Box.new(:horizontal, 6).tap do |container|
      container.visible = false
    end
  end
end
