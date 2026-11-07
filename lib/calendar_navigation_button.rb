# frozen_string_literal: true

require 'adwaita'
require_relative 'date_chooser'
require_relative 'date_time_utils'
require_relative 'utils'

# CalendarNavigationButton is the header bar's date control: a MenuButton
# whose label names the active month and year, opening a popover with a full
# DateChooser grid to jump around — or, when the current view has no concept
# of "a month" to navigate (upstream's agenda view), a plain heading label
# with the same text instead.
#
# Ported from upstream's src/gui/gcal-calendar-navigation-button.blp and
# src/gui/gcal-calendar-navigation-button.c.
#
class CalendarNavigationButton
  attr_reader :active_date, :active

  def initialize(**options)
    @active_date = options.fetch(:active_date, DateTimeUtils.start_of_day(Time.now))
    @active = options.fetch(:active, true)
    @handlers = []
  end

  def build
    bin.tap do |root|
      root.child = stack

      stack.tap do |container|
        container.add_named(button, 'active')
        container.add_named(static_label, 'inactive')
        container.visible_child_name = @active ? 'active' : 'inactive'
      end

      button.tap do |btn|
        btn.popover = popover
      end

      popover.tap do |pop|
        pop.child = date_chooser.build
      end

      date_chooser.on_day_selected { |date| self.active_date = date }

      update_label
    end
  end

  def widget = build

  # Upstream's GcalCalendarNavigationButton:active-date setter: pushes the
  # new date into both the button's label and the popover's grid. Handlers
  # only fire when the date actually moved, which is what keeps this from
  # bouncing forever against a caller that re-applies the same date after
  # being notified (window.rb pushes its active date back down here).
  def active_date=(date)
    changed = DateTimeUtils.compare_date(date, @active_date) != 0
    @active_date = date
    date_chooser.active_date = date
    update_label
    if changed
      @handlers.each { |handler| handler.call(@active_date) }
    end
    @active_date
  end

  # Upstream's GcalCalendarNavigationButton:active setter: swaps the stack
  # between the interactive button and the static heading.
  def active=(value)
    @active = value
    stack.visible_child_name = value ? 'active' : 'inactive'
    value
  end

  # Upstream's DateChooser day-selected pass-through.
  def on_day_selected(&block)
    @handlers << block
    block
  end

  def bin = @bin ||= Adwaita::Bin.new

  def stack = @stack ||= Gtk::Stack.new.tap { |widget| widget.hhomogeneous = false }

  def button
    @button ||= Gtk::MenuButton.new.tap do |widget|
      widget.use_underline = true
      widget.can_shrink = true
      widget.always_show_arrow = true
      widget.tooltip_text = 'Choose a Date'
    end
  end

  def static_label
    @static_label ||= Gtk::Label.new.tap do |widget|
      widget.add_css_class('heading')
      widget.margin_start = 9
      widget.margin_end = 9
    end
  end

  def popover
    @popover ||= Gtk::Popover.new.tap { |widget| widget.position = :bottom }
  end

  def date_chooser
    @date_chooser ||= DateChooser.new(
      split_month_year: true,
      active_date:      @active_date,
    )
  end

  private

    # Upstream's g_date_time_format (self->active_date, _("%OB %Y")).
    def update_label
      text = "#{Utils.month_name(@active_date.month - 1)} #{@active_date.year}"
      button.label = text
      static_label.label = text
      self
    end
end
