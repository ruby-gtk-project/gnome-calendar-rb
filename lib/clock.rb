# frozen_string_literal: true

require 'adwaita'

# Clock tells the rest of the app when the wall clock has moved on: every
# minute, every hour, and every day. The views use the day tick to re-draw
# "today", and the week grid uses the minute tick to move its now-strip.
#
# The timeout is always scheduled to land on the next whole minute rather than
# sixty seconds from now, so the ticks stay in step with the clock on screen.
# Resuming from suspend is noticed through logind's PrepareForSleep signal,
# which is how upstream catches a laptop that slept across midnight.
#
# Ported from upstream's src/core/gcal-clock.c.
#
class Clock
  def initialize
    @current = Time.now
    @handlers = { minute_changed: [], hour_changed: [], day_changed: [] }
    @source_id = nil
    watch_for_resume
    schedule_update
  end

  attr_reader :current

  # The three signals upstream declares. Each takes a block, and every block
  # registered for a signal runs when it fires.
  def on_minute_changed(&block) = register(:minute_changed, block)

  def on_hour_changed(&block) = register(:hour_changed, block)

  def on_day_changed(&block) = register(:day_changed, block)

  # Stops the clock. Nothing upstream does this — a GcalClock lives as long
  # as the context — but a test that builds one needs a way to let go of the
  # timeout.
  def stop
    unless @source_id.nil?
      GLib::Source.remove(@source_id)
      @source_id = nil
    end
    self
  end

  private

    def register(signal, block)
      @handlers.fetch(signal) << block
      block
    end

    # Upstream's update_current_date(): a day change implies an hour change,
    # which implies a minute change, and the signals fire outermost first.
    def update_current_date
      now = Time.now
      day_changed = now.year != @current.year || now.yday != @current.yday
      hour_changed = day_changed || now.hour != @current.hour
      minute_changed = hour_changed || now.min != @current.min

      @current = now

      if day_changed
        emit(:day_changed)
      end
      if hour_changed
        emit(:hour_changed)
      end
      if minute_changed
        emit(:minute_changed)
      end
      self
    end

    def emit(signal)
      @handlers.fetch(signal).each(&:call)
      self
    end

    # Upstream's schedule_update_timeout(): fire on the next whole minute.
    def schedule_update
      stop
      seconds_between = 60 - Time.now.sec
      @source_id = GLib::Timeout.add_seconds(seconds_between) do
        @source_id = nil
        update_current_date
        schedule_update
        GLib::Source::REMOVE
      end
      self
    end

    # Upstream's logind proxy: PrepareForSleep(false) means we are waking up,
    # and the clock may be far from where it was. A machine with no system
    # bus simply never gets the signal.
    def watch_for_resume
      @logind = Gio::DBusProxy.new(
        Gio::DBusConnection.new(:system),
        :none,
        nil,
        'org.freedesktop.login1',
        '/org/freedesktop/login1',
        'org.freedesktop.login1.Manager',
      )
      @logind.signal_connect('g-signal') do |_proxy, _sender, signal, parameters|
        if signal == 'PrepareForSleep' && parameters.get_child_value(0).value == false
          update_current_date
          schedule_update
        end
      end
      self
    rescue StandardError, NoMethodError
      self
    end
end
