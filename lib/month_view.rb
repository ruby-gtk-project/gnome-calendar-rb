# frozen_string_literal: true

require 'adwaita'
require_relative 'date_time_utils'
require_relative 'month_cell'
require_relative 'month_popover'
require_relative 'range'
require_relative 'settings'
require_relative 'style'
require_relative 'utils'
require_relative 'view'

# MonthView is the month grid: a header of weekday names, and six rows of
# seven day cells filled with the month on screen plus the days either side of
# it that round the grid out.
#
# Stepping forwards and backwards moves a month at a time, and time runs
# horizontally, which is what points the window's navigation buttons left and
# right rather than up and down.
#
# Upstream lays the cells out itself through GcalMonthViewRow so a multiday
# event can be drawn as one widget spanning several cells; the port puts the
# cells in a grid and gives each day its own widget for the event, which
# keeps every event reachable and every day clickable.
#
# Ported from upstream's src/gui/views/gcal-month-view.blp and
# src/gui/views/gcal-month-view.c.
#
class MonthView
  include View

  ROWS = 6
  COLUMNS = Utils::N_WEEKDAYS

  attr_reader :active_date

  def initialize(context)
    @context = context
    @active_date = DateTimeUtils.start_of_day(Time.now)
    @week_start = Utils.first_weekday
    @events = []
  end

  def build
    root_box.tap do |root|
      root.append(header_box)
      root.append(grid)

      header_box.tap do |box|
        weekday_labels.each { |label| box.append(label) }
      end

      grid.tap do |container|
        ROWS.times do |row|
          COLUMNS.times do |column|
            container.attach(
              cells[row][column].build,
              column,
              row,
              1,
              1,
            )
          end
        end
      end

      cells.flatten.each do |cell|
        cell.on_activated { |date, presses| on_cell_activated(date, presses) }
        cell.on_overflow { |date, events| popover.show_for(date, events, cell.cell) }
        cell.on_event_activated { |event, widget| emit_event_activated(event, widget) }
      end

      popover.tap do |widget|
        widget.on_event_activated { |event, event_widget| emit_event_activated(event, event_widget) }
        widget.on_new_event { |date| emit_create_event_detailed(day_range(date)) }
        widget.build
      end

      @context.weather_service.on_updated { fill_cells }

      initialise_headings
      refresh
    end
  end

  def widget = build

  # Upstream's GcalView::time-direction for the month view.
  def time_direction = :horizontal

  # Upstream's gcal_view_set_date().
  def active_date=(date)
    @active_date = date
    refresh
    date
  end

  # Upstream's gcal_view_get_next_date(): the same day next month.
  def next_date = DateTimeUtils.add_months(@active_date, 1)

  # Upstream's gcal_view_get_previous_date().
  def previous_date = DateTimeUtils.add_months(@active_date, -1)

  # The range the grid covers, which is what the view asks the manager for.
  def range
    first = grid_start
    CalendarRange.new(first, DateTimeUtils.add_days(first, ROWS * COLUMNS), CalendarRange::DEFAULT)
  end

  # Re-reads the events for the visible range and re-fills every cell.
  def refresh
    @events = @context.manager.events_in_range(range)
    fill_cells
    self
  end

  # Upstream's gcal_view_get_children_by_uuid().
  def children_by_uuid(_mod, uuid) = @events.select { |event| event.uuid == uuid }

  def root_box
    @root_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.add_css_class(Style::CALENDAR_VIEW)
      box.add_css_class('month-view')
      box.accessible_role = :grid
    end
  end

  def header_box
    @header_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.homogeneous = true
      box.add_css_class('header')
      box.add_css_class('heading')
      box.add_css_class('month-header')
      box.add_css_class('view')
    end
  end

  def weekday_labels
    @weekday_labels ||= Array.new(COLUMNS) do
      Gtk::Label.new('').tap do |label|
        label.margin_start = 12
        label.hexpand = true
        label.xalign = 0.0
      end
    end
  end

  def grid
    @grid ||= Gtk::Grid.new.tap do |container|
      container.row_homogeneous = true
      container.column_homogeneous = true
      container.vexpand = true
      container.hexpand = true
    end
  end

  def cells
    @cells ||= Array.new(ROWS) do
      Array.new(COLUMNS) do
        MonthCell.new(time_format: @context.time_format, event_widget_pool: @context.event_widget_pool)
      end
    end
  end

  def popover
    @popover ||= MonthPopover.new(
      time_format:       @context.time_format,
      event_widget_pool: @context.event_widget_pool,
    )
  end

  private

    def initialise_headings
      COLUMNS.times do |column|
        weekday_labels[column].text = Utils.weekday((column + @week_start) % COLUMNS)
      end
      self
    end

    # The first cell's date: the start of the week the first of the month
    # falls in.
    def grid_start
      first = Time.new(
        @active_date.year,
        @active_date.month,
        1,
        0,
        0,
        0,
      )
      DateTimeUtils.add_days(first, -((first.wday - @week_start) % COLUMNS))
    end

    # Hands every cell its date, its events and its selection state.
    def fill_cells
      start = grid_start

      (ROWS * COLUMNS).times do |index|
        date = DateTimeUtils.add_days(start, index)
        cell = cells[index / COLUMNS][index % COLUMNS]
        cell.date = date
        cell.other_month = date.month != @active_date.month
        cell.selected = DateTimeUtils.compare_date(date, @active_date).zero?
        cell.events = events_on(date)
        cell.weather = @context.weather_service.forecast_for(date) || [nil, nil]
      end
      self
    end

    def events_on(date)
      @events.select { |event| event.overlaps?(day_range(date)) }
    end

    def day_range(date)
      CalendarRange.new(date, DateTimeUtils.add_days(date, 1), CalendarRange::DEFAULT)
    end

    # One click moves the active date to the clicked day and asks the window
    # for a quick-add popover; two opens the full editor.
    def on_cell_activated(date, presses)
      self.active_date = date
      if presses >= 2
        emit_create_event_detailed(day_range(date))
      else
        emit_create_event(day_range(date), 0.0, 0.0)
      end
      self
    end
end
