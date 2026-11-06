# frozen_string_literal: true

require 'adwaita'
require 'gtk4'
require 'json'
require_relative 'meeting_row'
require_relative 'settings'
require_relative 'utils'

# EventPopover is what a click on an event opens: the summary, the date and
# time, a notes section (or a placeholder when there are none), the
# location, any meeting links found in the description, and a button that
# either edits the event or, for a read-only calendar, shows more detail.
#
# Ported from upstream's src/gui/gcal-event-popover.blp and
# src/gui/gcal-event-popover.c.
#
class EventPopover
  def initialize(context)
    @context = context
    @event = nil
    @edit_handlers = []
    @meeting_rows = []
  end

  attr_reader :event

  # Assembles the widget tree once; a second call is a no-op, which is what
  # lets a caller ask for the built popover without caring whether it
  # already exists.
  def build
    unless @assembled
      @assembled = assemble
    end
    @assembled
  end

  def widget = build

  # Points the popover at `parent` (the clicked event widget) and shows it
  # for `event`.
  def show_for(event, parent)
    build
    self.event = event
    unless @parent == parent
      unless @parent.nil?
        popover.unparent
      end
      @parent = parent
      popover.set_parent(parent)
    end
    popover.popup
    self
  end

  # Upstream's "edit" signal.
  def on_edit(&block)
    @edit_handlers << block
    block
  end

  def event=(event)
    @event = event
    refresh
    event
  end

  def popover
    @popover ||= Gtk::Popover.new.tap do |widget|
      widget.position = :top
      widget.width_request = 250
      widget.add_css_class('event-popover')
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |widget|
      widget.maximum_size = 400
      widget.tightening_threshold = 400
    end
  end

  def root_box = @root_box ||= Gtk::Box.new(:vertical, 0)

  def header_box
    @header_box ||= Gtk::Box.new(:horizontal, 18).tap do |box|
      box.margin_top = 18
      box.margin_bottom = 12
      box.margin_start = 18
      box.margin_end = 18
    end
  end

  def text_box
    @text_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.hexpand = true
    end
  end

  def summary_label
    @summary_label ||= Gtk::Label.new.tap do |label|
      label.selectable = true
      label.wrap = true
      label.wrap_mode = :word_char
      label.xalign = 0.0
      label.lines = 6
      label.ellipsize = :end
      label.add_css_class('title-4')
    end
  end

  def date_time_label
    @date_time_label ||= Gtk::Label.new.tap do |label|
      label.xalign = 0.0
      label.add_css_class('dimmed')
    end
  end

  def buttons_box = @buttons_box ||= Gtk::Box.new(:horizontal, 6)

  def read_only_icon
    @read_only_icon ||= Gtk::Image.new.tap do |image|
      image.icon_name = 'changes-prevent-symbolic'
      image.pixel_size = 18
      image.valign = :start
      image.halign = :end
      image.margin_top = 8
      image.margin_bottom = 8
      image.tooltip_text = 'This event is part of a read-only calendar'
      image.add_css_class('dimmed')
    end
  end

  def ics_export_button
    @ics_export_button ||= Gtk::Button.new.tap do |button|
      button.valign = :start
      button.halign = :end
      button.icon_name = 'share-symbolic'
      button.tooltip_text = 'Export Event'
      button.add_css_class('circular')
    end
  end

  def action_button
    @action_button ||= Gtk::Button.new.tap do |button|
      button.can_focus = true
      button.valign = :start
      button.halign = :end
      button.add_css_class('circular')
    end
  end

  def separator_1 = @separator_1 ||= Gtk::Separator.new(:horizontal)
  def separator_2 = @separator_2 ||= Gtk::Separator.new(:horizontal)
  def separator_3 = @separator_3 ||= Gtk::Separator.new(:horizontal)

  def placeholder_label
    @placeholder_label ||= Gtk::Label.new('No event notes').tap do |label|
      label.vexpand = true
      label.margin_top = 12
      label.margin_bottom = 12
      label.add_css_class('dimmed')
      label.add_css_class('no-events')
    end
  end

  def description_scrolled_window
    @description_scrolled_window ||= Gtk::ScrolledWindow.new.tap do |window|
      window.hscrollbar_policy = :never
      window.propagate_natural_height = true
      window.propagate_natural_width = true
      window.max_content_height = 350
    end
  end

  def description_label
    @description_label ||= Gtk::Label.new.tap do |label|
      label.use_markup = true
      label.selectable = true
      label.halign = :fill
      label.xalign = 0.0
      label.wrap = true
      label.wrap_mode = :word_char
      label.margin_top = 12
      label.margin_bottom = 18
      label.margin_start = 18
      label.margin_end = 18
    end
  end

  def location_box
    @location_box ||= Gtk::Box.new(:vertical, 0)
  end

  def location_inner_box
    @location_inner_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
      box.margin_top = 12
      box.margin_bottom = 12
      box.margin_start = 18
      box.margin_end = 18
    end
  end

  def location_text_box = @location_text_box ||= Gtk::Box.new(:vertical, 0)

  def location_heading_label
    @location_heading_label ||= Gtk::Label.new('Location').tap do |label|
      label.halign = :start
      label.add_css_class('heading')
    end
  end

  def location_label
    @location_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.selectable = true
      label.ellipsize = :end
    end
  end

  def map_button
    @map_button ||= Gtk::Button.new.tap do |button|
      button.halign = :end
      button.hexpand = true
      button.valign = :center
      button.tooltip_text = 'Open Location'
      button.icon_name = 'map-symbolic'
      button.add_css_class('circular')
    end
  end

  def meetings_box = @meetings_box ||= Gtk::Box.new(:vertical, 0)

  def meetings_listbox
    @meetings_listbox ||= Gtk::ListBox.new.tap do |listbox|
      listbox.selection_mode = :none
      listbox.margin_top = 12
      listbox.margin_bottom = 12
      listbox.margin_start = 18
      listbox.margin_end = 18
      listbox.add_css_class('calendar-list')
    end
  end

  private

    def assemble
      popover.tap do |widget|
        widget.default_widget = action_button
        widget.child = clamp

        clamp.tap { |c| c.child = root_box }

        root_box.tap do |box|
          box.append(header_box)
          box.append(separator_1)
          box.append(placeholder_label)
          box.append(description_scrolled_window)
          box.append(location_box)
          box.append(meetings_box)
        end

        header_box.tap do |box|
          box.append(text_box)
          box.append(buttons_box)
        end

        text_box.tap do |box|
          box.append(summary_label)
          box.append(date_time_label)
        end

        buttons_box.tap do |box|
          box.append(read_only_icon)
          box.append(ics_export_button)
          box.append(action_button)
        end

        description_scrolled_window.tap { |window| window.child = description_label }

        location_box.tap do |box|
          box.append(separator_2)
          box.append(location_inner_box)
        end

        location_inner_box.tap do |box|
          box.append(location_text_box)
          box.append(map_button)
        end

        location_text_box.tap do |box|
          box.append(location_heading_label)
          box.append(location_label)
        end

        meetings_box.tap do |box|
          box.append(separator_3)
          box.append(meetings_listbox)
        end

        action_button.signal_connect('clicked') { on_action_button_clicked }
        ics_export_button.signal_connect('clicked') { on_ics_export_button_clicked }
        map_button.signal_connect('clicked') { on_map_button_clicked }
      end
    end

    # Widget visibility is tracked here rather than read back from the
    # widgets: a GTK::Popover's children report their own GTK::Widget#visible?
    # against whether the popover itself is mapped, not the requested value,
    # so a predicate read straight after a setter can see the wrong thing
    # while the popover is still closed.
    def refresh
      if event.nil?
        self
      else
        refresh_for(event)
      end
    end

    def refresh_for(current)
      summary_label.label = current.summary
      description, meeting_url = Utils.extract_meeting_url(current.description)
      clear_meetings
      has_meeting = !meeting_url.nil?
      if has_meeting
        add_meeting(meeting_url)
      end
      has_description = setup_description(description)
      placeholder_label.visible = !has_description
      setup_location(current.location, has_meeting)
      date_time_label.label = current.format_date(@context.time_format)
      update_decorations(current)
      action_button.grab_focus
      self
    end

    def setup_description(description)
      markup = description.to_s.strip.gsub('<br>', "\n").gsub('&nbsp;', ' ')
      description_label.markup = markup
      visible = !markup.empty?
      description_scrolled_window.visible = visible
      visible
    end

    def setup_location(location, has_meeting)
      text = location.to_s.strip
      location_label.markup = text
      location_box.visible = !text.empty? && !has_meeting
      self
    end

    def clear_meetings
      @meeting_rows.each { |row| meetings_listbox.remove(row.widget) }
      @meeting_rows = []
      meetings_box.visible = false
      self
    end

    def add_meeting(url)
      row = MeetingRow.new(url)
      row.on_join_meeting { |meeting_url| on_join_meeting(meeting_url) }
      meetings_listbox.append(row.build)
      @meeting_rows << row
      meetings_box.visible = true
      self
    end

    def update_decorations(current)
      read_only = current.calendar&.read_only? || false
      read_only_icon.visible = read_only
      if read_only
        action_button.icon_name = 'info-outline-symbolic'
        action_button.tooltip_text = 'View Additional Details'
      else
        action_button.icon_name = 'edit-symbolic'
        action_button.tooltip_text = 'Edit Additional Details'
      end
      self
    end

    def on_action_button_clicked
      @edit_handlers.each { |handler| handler.call(@event) }
      popover.popdown
      self
    end

    def on_ics_export_button_clicked
      root = popover.root
      current = event
      popover.popdown
      if current.nil? || root.nil?
        self
      else
        dialog = Gtk::FileDialog.new
        dialog.title = 'Export Event'
        dialog.initial_name = "#{current.summary}.ics"
        dialog.save(root, nil) { |_source, result| on_file_dialog_save(dialog, result, current) }
        self
      end
    end

    def on_file_dialog_save(dialog, result, current)
      file = dialog.save_finish(result)
      contents = current.to_h.to_json
      file.replace_contents(
        contents,
        nil,
        false,
        :replace_destination,
      )
      self
    rescue GLib::Error
      self
    end

    def on_map_button_clicked
      root = popover.root
      location = event&.location.to_s.strip
      popover.popdown
      if root.nil? || location.empty?
        self
      else
        launcher = Gtk::UriLauncher.new("maps:q=#{location}")
        launcher.launch(root, nil) { |_source, _result| }
        self
      end
    end

    def on_join_meeting(url)
      root = popover.root
      popover.popdown
      if root.nil?
        self
      else
        launcher = Gtk::UriLauncher.new(url)
        launcher.launch(root, nil) { |_source, _result| }
        self
      end
    end
end
