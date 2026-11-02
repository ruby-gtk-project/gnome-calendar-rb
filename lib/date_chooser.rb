# frozen_string_literal: true

require 'adwaita'
require_relative 'date_chooser_day'
require_relative 'date_time_utils'
require_relative 'multi_choice'
require_relative 'range'
require_relative 'range_tree'
require_relative 'style'
require_relative 'utils'

# DateChooser is the little month grid in the sidebar: a heading that steps
# through months and years, a row of weekday initials, optional week numbers
# down the side, and six rows of seven days.
#
# The grid is always six rows of seven, filled with the tail of the previous
# month and the head of the next, which is what keeps it from changing height
# as the user steps through months.
#
# The heading comes in two shapes, as upstream's does: split into separate
# month and year controls (the sidebar), or one combined control whose value
# encodes year, month and day together (the header bar's popover).
#
# Ported from upstream's src/gui/common/gcal-date-chooser.blp and
# src/gui/common/gcal-date-chooser.c.
#
class DateChooser
  ROWS = 6
  COLUMNS = Utils::N_WEEKDAYS

  # The combined control's value encodes (year × 12 + month − 1) × 32 +
  # day − 1, which is upstream's encode_combined_choice_value().
  COMBINED_MIN = 384
  COMBINED_MAX = 3_839_998

  attr_reader :active_date

  def initialize(**options)
    @active_date = options.fetch(:active_date, DateTimeUtils.start_of_day(Time.now))
    @show_heading = options.fetch(:show_heading, true)
    @show_day_names = options.fetch(:show_day_names, true)
    @show_week_numbers = options.fetch(:show_week_numbers, false)
    @show_selected_week = options.fetch(:show_selected_week, false)
    @show_events = options.fetch(:show_events, true)
    @split_month_year = options.fetch(:split_month_year, false)
    @week_start = Utils.first_weekday
    @handlers = []
    @events = []
    @updating = false
  end

  def build
    bin.tap do |root|
      root.child = grid

      grid.tap do |container|
        container.attach(
          month_choice.build,
          0,
          0,
          1,
          1,
        )
        container.attach(
          year_choice.build,
          1,
          0,
          1,
          1,
        )
        container.attach(
          combined_choice.build,
          0,
          0,
          2,
          1,
        )
        container.attach(
          day_grid,
          0,
          1,
          2,
          1,
        )
      end

      day_grid.tap do |container|
        container.attach(
          corner,
          0,
          0,
          1,
          1,
        )

        COLUMNS.times do |column|
          container.attach(
            weekday_labels[column],
            column + 1,
            0,
            1,
            1,
          )
        end

        ROWS.times do |row|
          container.attach(
            week_number_labels[row],
            0,
            row + 1,
            1,
            1,
          )

          COLUMNS.times do |column|
            container.attach(
              days[row][column].build,
              column + 1,
              row + 1,
              1,
              1,
            )
          end
        end
      end

      days.flatten.each do |day|
        day.on_selected { |date| self.active_date = date }
      end

      month_choice.on_value_changed { split_choice_changed }
      year_choice.on_value_changed { split_choice_changed }
      month_choice.on_wrapped { year_choice.go_up }
      combined_choice.on_value_changed { combined_choice_changed }

      initialise_headings
      apply_visibility
      refresh
    end
  end

  def widget = build

  # Upstream's "day-selected" signal.
  def on_day_selected(&block)
    @handlers << block
    block
  end

  # Upstream's gcal_date_chooser_set_date(): moving to another month redraws
  # the grid, moving within one only moves the selection.
  def active_date=(date)
    clamped = clamp_to_month(date)
    month_changed = clamped.year != @active_date.year || clamped.month != @active_date.month
    changed = DateTimeUtils.compare_date(clamped, @active_date) != 0

    @active_date = clamped
    sync_headings

    if month_changed
      compute_days
      update_event_indicators
    end
    update_selected_day_display

    if changed
      @handlers.each { |handler| handler.call(@active_date) }
    end
    @active_date
  end

  # Upstream's GcalView::time-direction: the date chooser moves through time
  # downwards.
  def time_direction = :vertical

  def show_heading=(value)
    @show_heading = value
    apply_visibility
    value
  end

  def show_day_names=(value)
    @show_day_names = value
    apply_visibility
    value
  end

  def show_week_numbers=(value)
    @show_week_numbers = value
    apply_visibility
    value
  end

  def show_selected_week=(value)
    @show_selected_week = value
    update_selected_day_display
    value
  end

  def show_events=(value)
    @show_events = value
    update_event_indicators
    value
  end

  def split_month_year=(value)
    @split_month_year = value
    apply_visibility
    value
  end

  # Upstream's timeline subscriber: the events the chooser draws dots for.
  def events=(events)
    @events = events
    update_event_indicators
    events
  end

  # Recomputes the whole grid — the days, the dots and the selection.
  def refresh
    compute_days
    update_event_indicators
    update_selected_day_display
    self
  end

  def bin = @bin ||= Adwaita::Bin.new.tap { |widget| widget.add_css_class(Style::DATE_CHOOSER) }

  def grid = @grid ||= Gtk::Grid.new.tap { |container| container.orientation = :vertical }

  def day_grid
    @day_grid ||= Gtk::Grid.new.tap do |container|
      container.row_homogeneous = true
      container.column_homogeneous = true
    end
  end

  def corner = @corner ||= Gtk::Label.new('')

  def month_choice
    @month_choice ||= MultiChoice.new(
      min_value:               0,
      max_value:               11,
      wrap:                    true,
      category:                'Month',
      previous_button_tooltip: 'Previous Month',
      next_button_tooltip:     'Next Month',
    )
  end

  def year_choice
    @year_choice ||= MultiChoice.new(
      min_value:               1,
      max_value:               9999,
      category:                'Year',
      previous_button_tooltip: 'Previous Year',
      next_button_tooltip:     'Next Year',
    )
  end

  def combined_choice
    @combined_choice ||= MultiChoice.new(
      min_value:               COMBINED_MIN,
      max_value:               COMBINED_MAX,
      category:                'Month',
      previous_button_tooltip: 'Previous Month',
      next_button_tooltip:     'Next Month',
    )
  end

  # The weekday initials, in the order the locale's week starts.
  def weekday_labels
    @weekday_labels ||= Array.new(COLUMNS) do
      Gtk::Label.new('').tap { |widget| widget.add_css_class('weekday') }
    end
  end

  def week_number_labels
    @week_number_labels ||= Array.new(ROWS) do
      Gtk::Label.new('').tap { |widget| widget.add_css_class('weeknum') }
    end
  end

  def days
    @days ||= Array.new(ROWS) { Array.new(COLUMNS) { DateChooserDay.new } }
  end

  private

    # Upstream's calendar_init_weekday_display() and
    # calendar_init_month_display().
    def initialise_headings
      COLUMNS.times do |column|
        weekday_labels[column].text = Utils.grid_weekday((column + @week_start) % COLUMNS)
      end

      month_choice.choices = Utils::MONTH_NAMES
      combined_choice.format { |value| format_month_year(value) }
      combined_choice.step_callbacks(
        previous:   ->(value) { previous_combined_value(value) },
        next_value: ->(value) { next_combined_value(value) },
      )
      sync_headings
      self
    end

    # Upstream's format_month_year(): the year is dropped when it is the
    # current one.
    def format_month_year(value)
      year, month, = decode_combined(value)
      case year
      when Time.now.year then Utils.month_name(month - 1)
      else "#{Utils.month_name(month - 1)} #{year}"
      end
    end

    def decode_combined(value)
      day = (value % 32) + 1
      year_month = value / 32
      [year_month / 12, (year_month % 12) + 1, day]
    end

    def encode_combined(year, month, day) = (((year * 12) + month - 1) * 32) + day - 1

    # Upstream's compute_prev_combined_choice_value().
    def previous_combined_value(value)
      year, month, = decode_combined(value)
      month -= 1
      if month < 1
        month = 12
        year -= 1
      end
      encode_combined(year, month, 1)
    end

    # Upstream's compute_next_combined_choice_value().
    def next_combined_value(value)
      year, month, = decode_combined(value)
      month += 1
      if month > 12
        month = 1
        year += 1
      end
      encode_combined(year, month, 1)
    end

    # Pushes the active date into the three controls without letting their
    # change handlers bounce back.
    def sync_headings
      @updating = true
      month_choice.value = @active_date.month - 1
      year_choice.value = @active_date.year
      combined_choice.value = encode_combined(@active_date.year, @active_date.month, @active_date.day)
      @updating = false
      self
    end

    # Upstream's split_multi_choice_changed().
    def split_choice_changed
      unless @updating
        year = year_choice.value
        month = month_choice.value + 1
        day = [@active_date.day, DateTimeUtils.days_in_month(Time.new(year, month, 1))].min
        self.active_date = Time.new(
          year,
          month,
          day,
          0,
          0,
          0,
        )
      end
      self
    end

    # Upstream's combined_multi_choice_changed().
    def combined_choice_changed
      unless @updating
        year, month, day = decode_combined(combined_choice.value)
        self.active_date = Time.new(
          year,
          month,
          day,
          0,
          0,
          0,
        )
      end
      self
    end

    # Upstream's calendar_update_selected_day(): a day past the end of the
    # month it landed in is pulled back to the last day of that month.
    def clamp_to_month(date)
      length = DateTimeUtils.days_in_month(date)
      case date.day
      when ..length then date
      else Time.new(
        date.year,
        date.month,
        length,
        0,
        0,
        0,
      )
      end
    end

    # Upstream's calendar_compute_days(): the tail of the previous month, the
    # whole of this one, and as much of the next as fills six rows.
    def compute_days
      first = Time.new(
        @active_date.year,
        @active_date.month,
        1,
        0,
        0,
        0,
      )
      offset = (first.wday - @week_start) % COLUMNS
      grid_start = DateTimeUtils.add_days(first, -offset)

      (ROWS * COLUMNS).times do |index|
        date = DateTimeUtils.add_days(grid_start, index)
        day = days[index / COLUMNS][index % COLUMNS]
        day.date = date
        day.other_month = date.month != @active_date.month
      end

      ROWS.times do |row|
        last_of_row = days[row][COLUMNS - 1].date
        week_number_labels[row].text = DateTimeUtils.week_of_year(last_of_row).to_s
      end
      self
    end

    # Upstream's calendar_update_selected_day_display(): one day is selected,
    # and its whole row is highlighted when show-selected-week is set.
    def update_selected_day_display
      ROWS.times do |row|
        row_selected = false

        COLUMNS.times do |column|
          day = days[row][column]
          day_selected = DateTimeUtils.compare_date(day.date, @active_date).zero?
          day.selected = day_selected
          row_selected ||= day_selected
        end

        apply_row_class(row, row_selected && @show_selected_week)
      end
      self
    end

    def apply_row_class(row, present)
      COLUMNS.times do |column|
        if present
          days[row][column].button.add_css_class('current-week')
        else
          days[row][column].button.remove_css_class('current-week')
        end
      end
      present
    end

    # Upstream's update_event_indicators(): a dot under every day something
    # happens on.
    def update_event_indicators
      tree = RangeTree.new
      if @show_events
        @events.each { |event| tree.add_range(event.range, event) }
      end

      days.flatten.each do |day|
        day.has_dot = true
        day.dot_visible = tree.count_entries_at_range(day_range(day.date)).positive?
      end
      self
    end

    def day_range(date)
      CalendarRange.new(date, DateTimeUtils.add_days(date, 1), CalendarRange::DEFAULT)
    end

    # Upstream's get_split_choice_visible() / get_combined_choice_visible(),
    # plus the week-number column and the weekday row.
    def apply_visibility
      month_choice.box.visible = @show_heading && @split_month_year
      year_choice.box.visible = @show_heading && @split_month_year
      combined_choice.box.visible = @show_heading && !@split_month_year

      weekday_labels.each { |label| label.visible = @show_day_names }
      corner.visible = @show_day_names
      week_number_labels.each { |label| label.visible = @show_week_numbers }
      self
    end
end
