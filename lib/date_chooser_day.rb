# frozen_string_literal: true

require 'adwaita'
require_relative 'date_time_utils'
require_relative 'utils'

# DateChooserDay is one day button in the date chooser's grid: the day number,
# and a dot underneath when something happens that day.
#
# The style classes carry the state, exactly as upstream's do — `today`,
# `non-workday`, `other-month`, and `selected` for the day the chooser is on.
#
# Ported from upstream's src/gui/common/gcal-date-chooser-day.blp and
# src/gui/common/gcal-date-chooser-day.c.
#
class DateChooserDay
  attr_reader :date

  def initialize
    @date = nil
    @handlers = []
  end

  def build
    button.tap do |widget|
      widget.child = box

      box.tap do |container|
        container.append(label)
        container.append(dot_revealer)

        dot_revealer.tap do |revealer|
          revealer.child = dot
        end
      end

      widget.signal_connect('clicked') { @handlers.each { |handler| handler.call(@date) } }
    end
  end

  def widget = build

  # Upstream's "day-selected" signal, emitted by the button's click.
  def on_selected(&block)
    @handlers << block
    block
  end

  # Upstream's gcal_date_chooser_day_set_date(): the label, plus the `today`
  # and `non-workday` classes.
  def date=(value)
    @date = value
    label.text = value.day.to_s
    apply_class('today', DateTimeUtils.compare_date(value, Time.now).zero?)
    apply_class('non-workday', !Utils.workday?(value.wday % Utils::N_WEEKDAYS))
    value
  end

  # Upstream's gcal_date_chooser_day_set_other_month().
  def other_month=(other_month)
    apply_class('other-month', other_month)
    other_month
  end

  # Upstream's gcal_date_chooser_day_set_has_dot(): whether there is room
  # for a dot at all.
  def has_dot=(has_dot)
    dot_revealer.visible = has_dot
    has_dot
  end

  def has_dot? = dot_revealer.visible?

  # Upstream's gcal_date_chooser_day_set_dot_visible(): whether the dot is
  # revealed. A day with no room for a dot shows none either way.
  def dot_visible=(visible)
    dot_revealer.visible = visible
    dot_revealer.reveal_child = visible
    visible
  end

  def dot_visible? = dot_revealer.reveal_child?

  # Upstream's gcal_date_chooser_day_set_selected(): the selected day loses
  # its flat style so the accent fill shows.
  def selected=(selected)
    apply_class('selected', selected)
    apply_class('flat', !selected)
    selected
  end

  def selected? = button.has_css_class?('selected')

  def button
    @button ||= Gtk::Button.new.tap do |widget|
      widget.halign = :center
      widget.valign = :center
      widget.hexpand = true
      widget.vexpand = true
      widget.add_css_class('circular')
      widget.add_css_class('day')
      widget.add_css_class('flat')
      widget.add_css_class('text-button')
    end
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 0).tap do |container|
      container.valign = :center
    end
  end

  def label
    @label ||= Gtk::Label.new('0').tap do |widget|
      widget.halign = :center
      widget.valign = :center
      widget.width_chars = 2
      widget.add_css_class('day')
      widget.add_css_class('numeric')
    end
  end

  def dot_revealer
    @dot_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.halign = :center
      revealer.valign = :end
      revealer.transition_type = :crossfade
      revealer.visible = false
    end
  end

  def dot
    @dot ||= Adwaita::Bin.new.tap do |bin|
      bin.halign = :center
      bin.valign = :center
      bin.add_css_class('dot')
    end
  end

  private

    def apply_class(name, present)
      if present
        button.add_css_class(name)
      else
        button.remove_css_class(name)
      end
      present
    end
end
