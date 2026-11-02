# frozen_string_literal: true

require 'adwaita'
require_relative 'style'

# SyncIndicator is the little spinner in the header bar: nothing at all while
# idle, a spinner while the manager is synchronising, and a checkmark for a
# moment once it finishes.
#
# Ported from upstream's src/gui/gcal-sync-indicator.blp and
# src/gui/gcal-sync-indicator.c.
#
class SyncIndicator
  # How long the checkmark stays up after a sync finishes, in milliseconds —
  # upstream's SUCCESS_TIMEOUT.
  SUCCESS_TIMEOUT = 1500

  def initialize
    @timeout_id = nil
  end

  def build
    bin.tap do |root|
      root.child = stack

      stack.tap do |pages|
        pages.add_named(empty_box, 'empty')
        pages.add_named(spinner, 'spinner')
        pages.add_named(success_image, 'success')
        pages.visible_child_name = 'empty'
      end
    end
  end

  def widget = build

  # Upstream's gcal_sync_indicator_set_syncing(): starting shows the
  # spinner, stopping shows the checkmark and then fades back to nothing.
  def syncing=(syncing)
    cancel_timeout
    if syncing
      stack.visible_child_name = 'spinner'
    else
      show_success
    end
    syncing
  end

  def syncing? = stack.visible_child_name == 'spinner'

  def bin
    @bin ||= Adwaita::Bin.new.tap { |widget| widget.add_css_class(Style::SYNC_INDICATOR) }
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |pages|
      pages.transition_type = :crossfade
      pages.transition_duration = 250
    end
  end

  def empty_box = @empty_box ||= Gtk::Box.new(:horizontal, 0)

  def spinner
    @spinner ||= Adwaita::Spinner.new.tap do |widget|
      widget.tooltip_text = 'Synchronizing Remote Calendars'
    end
  end

  def success_image
    @success_image ||= Gtk::Image.new(icon_name: 'checkmark-small-symbolic')
  end

  private

    def show_success
      stack.visible_child_name = 'success'
      @timeout_id = GLib::Timeout.add(SUCCESS_TIMEOUT) do
        @timeout_id = nil
        stack.visible_child_name = 'empty'
        GLib::Source::REMOVE
      end
      self
    end

    def cancel_timeout
      unless @timeout_id.nil?
        GLib::Source.remove(@timeout_id)
        @timeout_id = nil
      end
      self
    end
end
