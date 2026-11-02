# frozen_string_literal: true

require 'adwaita'
require_relative 'date_time_utils'
require_relative 'event_widget'
require_relative 'settings'
require_relative 'style'

# MonthCell is one day in the month grid: the day number (or the month's name
# on the first of the month), as many events as fit, and a "+3" button that
# opens the rest in a popover.
#
# Upstream measures the cell at allocation time and fits as many event widgets
# as the height allows. The port composes the cell out of a box rather than
# laying it out by hand, so it shows a fixed number and overflows the rest —
# the same arithmetic, decided up front rather than per allocation.
#
# Ported from upstream's src/gui/views/gcal-month-cell.blp and
# src/gui/views/gcal-month-cell.c.
#
class MonthCell
  # How many events a cell shows before the overflow button takes over.
  MAX_VISIBLE_EVENTS = 3

  attr_reader :date, :events, :overflow

  def initialize(time_format: Settings::FORMAT_24H)
    @time_format = time_format
    @date = DateTimeUtils.start_of_day(Time.now)
    @events = []
    @overflow = 0
    @event_widgets = []
    @overflow_handlers = []
    @activate_handlers = []
    @event_activated_handlers = []
  end

  def build
    cell.tap do |root|
      root.append(header_box)
      root.append(content_space)
      root.append(overflow_button)

      header_box.tap do |box|
        box.append(day_label)
        box.append(weather_icon)
        box.append(temp_label)
      end

      content_space.tap do |box|
        box.vexpand = true
      end

      overflow_button.tap do |button|
        button.child = overflow_inscription
        button.signal_connect('clicked') do
          @overflow_handlers.each { |handler| handler.call(@date, @events) }
        end
      end

      cell.add_controller(click_gesture)
      click_gesture.tap do |gesture|
        gesture.signal_connect('released') do |_gesture, presses, _x, _y|
          on_released(presses)
        end
      end

      refresh
    end
  end

  def widget = build

  # Upstream's overflow_button_clicked_cb(): the cell asks the view to open
  # the day's popover.
  def on_overflow(&block)
    @overflow_handlers << block
    block
  end

  # A click on empty space in the cell: the view turns this into a
  # create-event, and a double click into create-event-detailed.
  def on_activated(&block)
    @activate_handlers << block
    block
  end

  def on_event_activated(&block)
    @event_activated_handlers << block
    block
  end

  # Upstream's gcal_month_cell_set_date(): the first of the month shows the
  # month's name instead of "1".
  def date=(value)
    @date = value
    if value.day == 1
      day_label.text = value.strftime('%B')
      day_label.add_css_class('first-day')
    else
      day_label.text = value.day.to_s
      day_label.remove_css_class('first-day')
    end
    update_style_flags
    value
  end

  # The events happening on this day, in order. Everything past
  # MAX_VISIBLE_EVENTS becomes the overflow count.
  def events=(events)
    @events = events
    rebuild_event_widgets
    events
  end

  # Upstream's gcal_month_cell_set_selected().
  def selected=(selected)
    apply_class('selected', selected)
    selected
  end

  def selected? = cell.has_css_class?('selected')

  # Whether this cell belongs to the month either side of the one on screen.
  def other_month=(other_month)
    apply_class('other-month', other_month)
    other_month
  end

  # Upstream's update_weather(): the icon and temperature the weather
  # service reported for this day, or nothing.
  def weather=(weather)
    icon_name, temperature = weather
    weather_icon.icon_name = icon_name.to_s
    weather_icon.visible = !icon_name.nil?
    temp_label.text = temperature.to_s
    temp_label.visible = !temperature.nil?
    weather
  end

  def time_format=(time_format)
    @time_format = time_format
    rebuild_event_widgets
    time_format
  end

  def refresh
    self.date = @date
    rebuild_event_widgets
    self
  end

  def cell
    @cell ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.add_css_class(Style::MONTH_CELL)
      box.focusable = true
      box.accessible_role = :grid_cell
      box.width_request = 50
      box.height_request = 50
    end
  end

  def header_box
    @header_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.margin_top = 6
      box.margin_bottom = 6
      box.margin_start = 6
      box.margin_end = 6
    end
  end

  def day_label
    @day_label ||= Gtk::Label.new.tap do |label|
      label.add_css_class('day-label')
      label.add_css_class('numeric')
    end
  end

  def weather_icon
    @weather_icon ||= Gtk::Image.new.tap do |image|
      image.pixel_size = 16
      image.margin_start = 12
      image.accessible_role = :presentation
      image.visible = false
      image.add_css_class('dimmed')
    end
  end

  def temp_label
    @temp_label ||= Gtk::Label.new.tap do |label|
      label.visible = false
      label.add_css_class('dimmed')
      label.add_css_class('temp-label')
    end
  end

  def content_space = @content_space ||= Gtk::Box.new(:vertical, 1)

  def overflow_button
    @overflow_button ||= Gtk::Button.new.tap do |button|
      button.tooltip_text = 'All Events'
      button.margin_top = 1
      button.margin_start = 1
      button.margin_bottom = 2
      button.margin_end = 2
      button.visible = false
      button.add_css_class('flat')
      button.add_css_class('overflow')
    end
  end

  def overflow_inscription
    @overflow_inscription ||= Gtk::Inscription.new.tap do |inscription|
      inscription.text_overflow = :ellipsize_end
    end
  end

  def click_gesture = @click_gesture ||= Gtk::GestureClick.new.tap { |gesture| gesture.button = 1 }

  private

    # Upstream's update_style_flags(): today's cell is marked so the day
    # label gets the accent pill.
    def update_style_flags
      apply_class('today', DateTimeUtils.compare_date(@date, Time.now).zero?)
      self
    end

    def apply_class(name, present)
      if present
        cell.add_css_class(name)
      else
        cell.remove_css_class(name)
      end
      present
    end

    # Fills the content space with the first MAX_VISIBLE_EVENTS events and
    # sets the overflow count from the rest, as
    # gcal_month_cell_set_overflow() does.
    def rebuild_event_widgets
      @event_widgets.each { |event_widget| content_space.remove(event_widget.button) }
      @event_widgets = @events.first(MAX_VISIBLE_EVENTS).map { |event| build_event_widget(event) }
      @event_widgets.each { |event_widget| content_space.append(event_widget.button) }

      @overflow = [@events.length - MAX_VISIBLE_EVENTS, 0].max
      overflow_button.visible = @overflow.positive?
      overflow_inscription.text = overflow_text
      self
    end

    def overflow_text
      case @overflow
      when 0 then ''
      else "+#{@overflow}"
      end
    end

    def build_event_widget(event)
      EventWidget.new(event, time_format: @time_format).tap do |event_widget|
        event_widget.on_activated do |activated, widget|
          @event_activated_handlers.each { |handler| handler.call(activated, widget) }
        end
        event_widget.build
      end
    end

    # One click selects the day; a double click asks for the editor.
    def on_released(presses)
      @activate_handlers.each { |handler| handler.call(@date, presses) }
      self
    end
end
