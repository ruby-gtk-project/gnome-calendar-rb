# frozen_string_literal: true

require 'digest'
require 'adwaita'

# Style is the app's stylesheet. Upstream ships src/theme/style.css and
# src/theme/events.css inside a GResource and loads them at startup; the port
# carries the same rules here and installs them on the default display.
#
# Upstream gives several of its widgets a CSS node name of their own
# (`datechooser`, `monthcell`, `event`, …) by calling
# gtk_widget_class_set_css_name on a subclass. The port composes widgets
# rather than subclassing them, so each of those names becomes a style class
# the widget adds to itself, and the selectors below follow.
#
# Ported from upstream's src/theme/style.css and src/theme/events.css.
#
module Style
  # The style classes that stand in for upstream's CSS node names, so the
  # widgets and the stylesheet cannot drift apart.
  DATE_CHOOSER = 'datechooser'
  MONTH_CELL = 'monthcell'
  EVENT = 'event'
  SYNC_INDICATOR = 'syncindicator'
  CALENDAR_VIEW = 'calendar-view'
  AGENDA_DAY_ROW = 'agendaviewdayrow'

  CSS = <<~CSS
    /* Header labels */
    .calendar-view {
      font-size: 10pt;
    }

    .calendar-view box.header label {
      opacity: var(--dim-opacity);
    }

    .calendar-view.current {
      background-color: rgb(from var(--accent-bg-color) r g b / 30%);
    }

    /* Calendar list */
    .calendar-list {
      background-color: transparent;
    }

    .calendar-list > row {
      background-color: transparent;
      border-radius: 10px;
    }

    .calendar-color-image {
      border-radius: 50%;
    }

    /* Date chooser: week numbers, with a style resembling GNOME Shell's */
    .datechooser {
      padding: 6px;
    }

    .datechooser .weeknum {
      font-size: smaller;
      font-weight: bold;
      margin: 6px;
      padding: 4px;
      border-radius: 5px;
      background-color: rgb(from currentColor r g b / 5%);
      opacity: var(--dim-opacity);
    }

    /* Day names */
    .datechooser .weekday {
      font-size: smaller;
      font-weight: bold;
      opacity: var(--dim-opacity);
    }

    /* Days */
    .datechooser button.day {
      font-size: 10pt;
      font-weight: normal;
      min-height: 26px;
      min-width: 26px;
      margin: 2px;
      padding: 3px;
      transition: none;
    }

    .datechooser button.day dot,
    .datechooser button.day .dot {
      background-color: var(--window-fg-color);
      border-radius: 50%;
      min-height: 3px;
      min-width: 3px;
    }

    .datechooser button.day.non-workday {
      opacity: var(--dim-opacity);
    }

    .datechooser button.day:selected,
    .datechooser button.day.selected {
      background-color: var(--accent-bg-color);
      color: var(--accent-fg-color);
      font-weight: bold;
    }

    .datechooser button.day.today {
      color: var(--accent-color);
    }

    .datechooser button.day.today.selected {
      background-color: var(--accent-bg-color);
      color: var(--accent-fg-color);
    }

    .datechooser button.day.other-month {
      opacity: 0.5;
    }

    .datechooser .current-week {
      background: rgb(from currentColor r g b / 10%);
      border-radius: 9px;
    }

    /* Month cell */
    .monthcell {
      transition: background-color 200ms;
    }

    .monthcell .overflow {
      border-radius: 6px;
    }

    .monthcell .day-label {
      border-radius: 6px;
      padding: 0 6px 0 6px;
    }

    .monthcell label.first-day {
      font-weight: 700;
    }

    .monthcell.today label.day-label {
      font-weight: 700;
      color: var(--accent-fg-color);
      background-color: var(--accent-bg-color);
    }

    .monthcell.selected {
      background-color: rgb(from var(--accent-bg-color) r g b / 17%);
    }

    .monthcell.other-month .day-label {
      opacity: 0.5;
    }

    .monthcell button {
      font-weight: normal;
      padding: 0 4px;
      border-radius: 0;
    }

    .calendar-view.month-view > box.month-header {
      padding-bottom: 6px;
    }

    /* Agenda view */
    .agendaviewdayrow {
      margin-left: 9px;
      margin-right: 9px;
      margin-bottom: 3px;
    }

    .agendaviewdayrow > box > label {
      padding: 6px 0;
    }

    .agendaviewdayrow list > row,
    .agendaviewdayrow list > label {
      border-radius: 6px;
      background: none;
    }

    label.no-events {
      font-style: italic;
    }

    /* Sync indicator */
    .syncindicator {
      padding: 6px;
    }

    /* Events — from events.css */
    .event {
      border-radius: 6px;
      font-size: 0.9rem;
    }

    .event .edge {
      min-width: 6px;
    }

    .event .content {
      margin: 4px;
    }

    .calendar-view.month-view .event {
      margin: 0 1px 0 1px;
    }

    /* Removes the default drop-target style, as upstream does */
    .drop-target:drop(active) {
      box-shadow: none;
    }

    .drop-overlay-area {
      background-color: rgb(from var(--accent-bg-color) r g b / 25%);
    }
  CSS

  module_function

  # Installs the stylesheet on the default display, at upstream's
  # GTK_STYLE_PROVIDER_PRIORITY_APPLICATION.
  def install
    Gtk::StyleContext.add_provider_for_display(
      Gdk::Display.default,
      provider,
      Gtk::StyleProvider::PRIORITY_APPLICATION,
    )
    provider
  end

  def provider
    @provider ||= Gtk::CssProvider.new.tap { |css| css.load_from_data(CSS) }
  end

  # Upstream gives each event widget its own --event-bg-color through a
  # per-calendar CSS snippet generated at runtime (gcal-window.c's
  # colors_provider). The port does the same: asking for a colour's class
  # name adds a rule for it, so an event widget only has to add the class.
  def color_class(rgba)
    key = rgba.to_s
    classes[key] ||= register_color(key)
  end

  def classes = @classes ||= {}

  def color_provider
    @color_provider ||= Gtk::CssProvider.new.tap do |css|
      Gtk::StyleContext.add_provider_for_display(
        Gdk::Display.default,
        css,
        Gtk::StyleProvider::PRIORITY_APPLICATION + 1,
      )
    end
  end

  # Builds the class name, appends its rules, and reloads the dynamic
  # provider with everything registered so far.
  def register_color(key)
    "event-color-#{Digest::MD5.hexdigest(key)[0, 8]}".tap do |name|
      rules[name] = <<~RULE
        .#{name} {
          background-color: color-mix(in srgb, #{key} 25%, var(--view-bg-color));
        }

        .#{name} .edge {
          background-color: #{key};
        }

        .#{name}.dot {
          background-color: #{key};
        }
      RULE
      color_provider.load_from_data(rules.values.join("\n"))
    end
  end

  def rules = @rules ||= {}
end
