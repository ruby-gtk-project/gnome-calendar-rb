# frozen_string_literal: true

require 'adwaita'
require_relative 'clock'
require_relative 'event_widget_pool'
require_relative 'manager'
require_relative 'settings'

# Context is the single object every widget is handed: the clock, the manager,
# the settings, the system time zone and the user's 12h/24h preference. It
# exists so that no widget has to reach for a global.
#
# The time format comes from the settings portal's
# org.gnome.desktop.interface clock-format, as upstream reads it, and the
# context re-reads it when the portal says it changed.
#
# Ported from upstream's src/core/gcal-context.c.
#
class Context
  attr_reader :clock, :manager, :settings, :time_format, :timezone

  def initialize(settings: nil, manager: nil)
    @settings = settings || Settings.new
    @manager = manager || Manager.new
    @clock = Clock.new
    @time_format = Settings::FORMAT_24H
    @timezone = Time.now.zone
    @handlers = { time_format_changed: [], timezone_changed: [] }
    watch_settings_portal
  end

  # The event widget pool every view's event widgets are taken from and
  # reclaimed into, shared across the whole application.
  def event_widget_pool = @event_widget_pool ||= EventWidgetPool.new(time_format: @time_format)

  # Upstream's gcal_context_startup().
  def startup
    read_time_format
    manager.startup
    self
  end

  def on_time_format_changed(&block) = register(:time_format_changed, block)

  def on_timezone_changed(&block) = register(:timezone_changed, block)

  # The strftime format the views show a time of day in.
  def hour_format
    case time_format
    when Settings::FORMAT_12H then '%I:%M %p'
    else '%R'
    end
  end

  private

    def register(signal, block)
      @handlers.fetch(signal) << block
      block
    end

    def notify(signal)
      @handlers.fetch(signal).each(&:call)
      self
    end

    # Upstream's read_time_format(): one ReadOne against the portal. Without
    # a portal the 24h default upstream initialises to stands.
    def read_time_format
      answer = settings_portal&.call_sync(
        'ReadOne',
        GLib::Variant.new(['org.gnome.desktop.interface', 'clock-format']),
        :none,
        -1,
      )
      unless answer.nil?
        apply_time_format(answer.get_child_value(0).value.to_s)
      end
      self
    rescue StandardError, NoMethodError
      self
    end

    def apply_time_format(value)
      format = Settings::FORMAT_24H
      if value == '12h'
        format = Settings::FORMAT_12H
      end

      unless format == @time_format
        @time_format = format
        notify(:time_format_changed)
      end
      @time_format
    end

    # Upstream's on_settings_portal_changed_cb(): the portal tells us when
    # the desktop's clock format changes under us.
    def watch_settings_portal
      settings_portal&.signal_connect('g-signal') do |_proxy, _sender, signal, parameters|
        if signal == 'SettingChanged' && parameters.get_child_value(1).value.to_s == 'clock-format'
          apply_time_format(parameters.get_child_value(2).value.to_s)
        end
      end
      self
    rescue StandardError, NoMethodError
      self
    end

    def settings_portal
      @settings_portal ||= Gio::DBusProxy.new(
        Gio::DBusConnection.new(:session),
        :none,
        nil,
        'org.freedesktop.portal.Desktop',
        '/org/freedesktop/portal/desktop',
        'org.freedesktop.portal.Settings',
      )
    rescue StandardError, NoMethodError
      nil
    end
end
