# frozen_string_literal: true

require 'json'
require 'fileutils'

# Settings holds the same keys as upstream's org.gnome.calendar GSettings
# schema, plus the time format the context reads from the settings portal.
#
# Upstream uses GSettings, which needs a schema compiled and installed into
# the system's glib-2.0/schemas directory. Requiring an install step to run
# the app from a checkout is worse than the alternative, so the same keys,
# defaults and semantics are backed by a small JSON file under
# XDG_CONFIG_HOME instead.
#
# Ported from upstream's data/org.gnome.calendar.gschema.xml.in.
#
class Settings
  # Upstream's GcalTimeFormat.
  FORMAT_12H = :format_12h
  FORMAT_24H = :format_24h

  # Upstream's GcalWindowView, in the order the enum declares — the index is
  # what the win.change-view action takes.
  VIEWS = %w[month week agenda].freeze

  DEFAULTS = {
    'window-maximized'           => true,
    'window-width'               => 768,
    'window-height'              => 600,
    'active-view'                => 'month',
    'weather-show-weather'       => true,
    'weather-automatic-location' => true,
    'weather-location-name'      => '',
    'week-view-zoom-level'       => 1.0,
  }.freeze

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
  end

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = value
    write
    value
  end

  def location = @path

  # Named accessors for every key, so callers do not repeat the strings.
  DEFAULTS.each_key do |key|
    method_name = key.tr('-', '_')
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
    if DEFAULTS[key].is_a?(TrueClass) || DEFAULTS[key].is_a?(FalseClass)
      define_method(:"#{method_name}?") { self[key] == true }
    end
  end

  # Upstream's window-size is one (ii) tuple; the port stores the two halves
  # separately and hands them back together.
  def window_size = [self['window-width'], self['window-height']]

  def window_size=(size)
    self['window-width'] = size[0]
    self['window-height'] = size[1]
    size
  end

  # The index of the saved active view, which is what the window's
  # change-view action speaks in.
  def active_view_index = VIEWS.index(self['active-view']) || 0

  def active_view_index=(index)
    self['active-view'] = VIEWS.fetch(index % VIEWS.length)
    index
  end

  # Restores the geometry recorded by the previous run.
  def apply_to(window)
    window.set_default_size(*window_size)
    if window_maximized?
      window.maximize
    end
  end

  # Records the geometry for the next run.
  def save_from(window)
    unless window.maximized?
      self.window_size = [window.default_width, window.default_height]
    end
    self['window-maximized'] = window.maximized?
    self
  end

  private

    def default_path
      base = ENV['XDG_CONFIG_HOME'] || File.join(Dir.home, '.config')
      File.join(base, 'gnome-calendar-rb', 'settings.json')
    end

    def read
      JSON.parse(File.read(@path))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, "#{JSON.pretty_generate(@values)}\n")
      self
    rescue SystemCallError
      self
    end
end
