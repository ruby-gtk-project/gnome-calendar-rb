# frozen_string_literal: true

require 'adwaita'

# Timer fires a callback every `duration` seconds, and can be reset so the
# next tick is a full duration away again — which is what the weather service
# and the sync indicator use it for.
#
# Upstream implements it as a bespoke GSource so a reset is one
# set_ready_time; the port re-arms a GLib timeout instead, which gives the
# same observable behaviour: a reset postpones the next tick, a stop cancels
# it, and changing the duration while running either fires at once (the new
# duration has already elapsed) or re-schedules.
#
# Ported from upstream's src/core/gcal-timer.c.
#
class Timer
  attr_reader :default_duration

  def initialize(default_duration)
    unless default_duration.positive?
      raise ArgumentError, 'duration must be positive'
    end

    @default_duration = default_duration
    @last_event = nil
    @source_id = nil
    @callback = nil
  end

  # Upstream's gcal_timer_set_callback(). The block is handed the timer, as
  # the GCalTimerFunc is.
  def callback(&block)
    @callback = block
    self
  end

  # Upstream's gcal_timer_is_running().
  def running? = !@source_id.nil?

  # Upstream's gcal_timer_start().
  def start
    unless running?
      @last_event = monotonic_now
      schedule_next
    end
    self
  end

  # Upstream's gcal_timer_reset(): the next tick is a full duration from now.
  def reset
    if running?
      @last_event = monotonic_now
      schedule_next
    end
    self
  end

  # Upstream's gcal_timer_stop().
  def stop
    unless @source_id.nil?
      GLib::Source.remove(@source_id)
      @source_id = nil
    end
    self
  end

  # Upstream's gcal_timer_set_default_duration(): a running timer whose new
  # duration has already elapsed fires immediately.
  def default_duration=(duration)
    unless duration.positive?
      raise ArgumentError, 'duration must be positive'
    end

    @default_duration = duration
    if running?
      schedule_next
    end
    duration
  end

  private

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Arms the next tick, firing at once when the duration has already
    # elapsed since the last event.
    def schedule_next
      stop
      remaining = @last_event + @default_duration - monotonic_now
      @source_id = GLib::Timeout.add(milliseconds_from(remaining)) { fire }
      self
    end

    def milliseconds_from(seconds)
      case seconds
      when ..0 then 0
      else (seconds * 1000).round
      end
    end

    # One tick: run the callback, remember when it happened, and arm the
    # next one.
    def fire
      @source_id = nil
      @callback&.call(self)
      @last_event = monotonic_now
      schedule_next
      GLib::Source::REMOVE
    end
end
