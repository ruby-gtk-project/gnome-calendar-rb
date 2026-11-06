# frozen_string_literal: true

require 'gtk4'
require_relative 'utils'

# MeetingRow is one row in an event popover's "join the meeting" list: a
# title, a subtitle holding the URL, and a Join button.
#
# Ported from upstream's src/gui/gcal-meeting-row.blp and
# src/gui/gcal-meeting-row.c.
#
class MeetingRow
  def initialize(url)
    @url = url
    @join_handlers = []
  end

  attr_reader :url

  def build
    row.tap do |widget|
      widget.child = content_box

      content_box.tap do |container|
        container.append(text_box)
        container.append(join_button)
      end

      text_box.tap do |container|
        container.append(title_label)
        container.append(subtitle_label)
      end

      join_button.signal_connect('clicked') do
        @join_handlers.each { |handler| handler.call(@url) }
      end

      refresh
    end
  end

  def widget = build

  # Upstream's "join-meeting" signal.
  def on_join_meeting(&block)
    @join_handlers << block
    block
  end

  def row
    @row ||= Gtk::ListBoxRow.new.tap do |widget|
      widget.activatable = false
      widget.selectable = false
    end
  end

  def content_box = @content_box ||= Gtk::Box.new(:horizontal, 6)

  def text_box
    @text_box ||= Gtk::Box.new(:vertical, 0).tap do |container|
      container.hexpand = true
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.add_css_class('heading')
    end
  end

  def subtitle_label
    @subtitle_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.single_line_mode = true
      label.ellipsize = :end
      label.use_markup = true
    end
  end

  def join_button
    @join_button ||= Gtk::Button.new.tap do |button|
      button.halign = :end
      button.valign = :center
      button.margin_start = 12
      button.use_underline = true
      button.label = '_Join'
      button.add_css_class('suggested-action')
    end
  end

  private

    def refresh
      title_label.text = Utils.service_name_from_url(@url) || 'Unknown Service'
      subtitle_label.markup = format('<a title="%<url>s" href="%<url>s">%<url>s</a>', url: @url)
      self
    end
end
