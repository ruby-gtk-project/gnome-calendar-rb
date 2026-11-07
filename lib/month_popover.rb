# frozen_string_literal: true

require 'adwaita'
require_relative 'date_time_utils'
require_relative 'event_widget'
require_relative 'event_widget_pool'
require_relative 'settings'

# MonthPopover is what a month cell's "+3 more" button opens: the day's
# number, every event on that day, and a button to add another one.
#
# Upstream draws it as a widget of its own that it animates into place over
# the cell; the port uses a GtkPopover pointed at the cell, which gets the
# same dismissal behaviour (Escape, click outside) for free.
#
# Ported from upstream's src/gui/views/gcal-month-popover.blp and
# src/gui/views/gcal-month-popover.c.
#
class MonthPopover
  attr_reader :date

  def initialize(time_format: Settings::FORMAT_24H, event_widget_pool: nil)
    @time_format = time_format
    @event_widget_pool = event_widget_pool || EventWidgetPool.new(time_format: time_format)
    @date = DateTimeUtils.start_of_day(Time.now)
    @events = []
    @parent = nil
    @event_widgets = []
    @event_activated_handlers = []
    @new_event_handlers = []
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
      widget.child = main_box

      main_box.tap do |container|
        container.append(header_box)
        container.append(listbox)
        container.append(new_event_button)

        header_box.tap do |box|
          box.append(day_label)
          box.append(close_button)
        end
      end

      close_button.tap do |button|
        button.signal_connect('clicked') { popover.popdown }
      end

      new_event_button.tap do |button|
        button.signal_connect('clicked') do
          popover.popdown
          @new_event_handlers.each { |handler| handler.call(@date) }
        end
      end

      refresh
    end
  end

  def widget = build

  def on_event_activated(&block)
    @event_activated_handlers << block
    block
  end

  def on_new_event(&block)
    @new_event_handlers << block
    block
  end

  # Upstream's gcal_month_popover_set_date() plus its event list: the cell
  # hands over the day it stands for and everything happening on it.
  def show_for(date, events, parent)
    @date = date
    @events = events
    refresh
    unless @parent == parent
      @parent = parent
      popover.set_parent(parent)
    end
    popover.popup
    self
  end

  def refresh
    day_label.text = @date.day.to_s
    rebuild_rows
    self
  end

  def time_format=(time_format)
    @time_format = time_format
    refresh
    time_format
  end

  def popover
    @popover ||= Gtk::Popover.new.tap do |widget|
      widget.position = :bottom
      widget.has_arrow = true
      widget.add_css_class('monthpopover')
    end
  end

  def main_box = @main_box ||= Gtk::Box.new(:vertical, 12).tap { |box| box.add_css_class('view') }

  def header_box = @header_box ||= Gtk::Box.new(:horizontal, 0)

  def day_label
    @day_label ||= Gtk::Label.new('12').tap do |label|
      label.xalign = 0.0
      label.hexpand = true
      label.add_css_class('large-title')
    end
  end

  def close_button
    @close_button ||= Gtk::Button.new(icon_name: 'window-close-symbolic').tap do |button|
      button.halign = :end
      button.valign = :start
      button.focusable = false
      button.add_css_class('flat')
      button.add_css_class('circular')
    end
  end

  def listbox
    @listbox ||= Gtk::ListBox.new.tap do |list|
      list.vexpand = true
      list.selection_mode = :none
      list.add_css_class('calendar-list')
    end
  end

  def new_event_button
    @new_event_button ||= Gtk::Button.new(label: 'New Event…').tap do |button|
      button.add_css_class('flat')
    end
  end

  private

    def rebuild_rows
      @rows ||= []
      @rows.each { |row| row.child = nil }
      @rows.each { |row| listbox.remove(row) }
      @event_widgets.each { |event_widget| @event_widget_pool.reclaim(event_widget) }
      @event_widgets = []
      @rows = @events.map { |event| build_row(event) }
      @rows.each { |row| listbox.append(row) }
      self
    end

    def build_row(event)
      event_widget = @event_widget_pool.take_or_create(event, time_format: @time_format).tap do |widget|
        widget.on_activated do |activated, inner|
          popover.popdown
          @event_activated_handlers.each { |handler| handler.call(activated, inner) }
        end
      end
      @event_widgets << event_widget

      Gtk::ListBoxRow.new.tap do |row|
        row.activatable = false
        row.child = event_widget.button
      end
    end
end
