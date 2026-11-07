# frozen_string_literal: true

require 'libgweather'
require_relative 'date_time_utils'

# WeatherService is the icon and temperature MonthCell shows next to the day
# number: upstream's GcalWeatherService, which wraps a GWeatherInfo and keeps
# it refreshed against a GWeatherLocation.
#
# Upstream finds the location two ways: the user's own choice
# (weather-location-name) or, failing that, geoclue's automatic position.
# ashpd — the portal binding this app otherwise uses — has no Location portal
# in this gem's version (its Ruby surface is Account, Camera, OpenUri,
# Screenshot, Settings and Trash only), so "automatic" location has nothing
# to ask; only a named location resolves to a forecast. That is a real gap,
# not a stub: a nil location simply means no forecast to show, which is the
# port's existing no-data behaviour (the icon and label start invisible).
#
# Ported from upstream's src/weather/gcal-weather-service.c.
#
class WeatherService
  # Upstream's application-id / contact-info construct properties: GWeather
  # refuses to call gweather_info_update() without them, since they go out as
  # request metadata to whichever provider answers.
  APPLICATION_ID = 'org.gnome.Calendar'
  CONTACT_INFO = 'https://github.com/ruby-gtk-project/gnome-calendar-rb'

  def initialize(settings)
    @settings = settings
    @forecasts = {}
    @info = nil
    @updated_handlers = []
  end

  def on_updated(&block)
    @updated_handlers << block
    block
  end

  # The [icon_name, temperature] MonthCell#weather= wants for @date, or nil
  # when there is nothing to show yet (before the first update lands, or when
  # the location cannot be resolved).
  def forecast_for(date)
    @forecasts[DateTimeUtils.start_of_day(date).to_date]
  end

  # Upstream's gcal_weather_service_run(): (re)points the GWeatherInfo at the
  # configured location and asks it to update. The update is async — GWeather
  # talks to the network — so this returns immediately and the forecast
  # fills in through the "updated" signal.
  def refresh
    unless @settings.weather_show_weather?
      @forecasts = {}
      return self
    end

    location.then do |found|
      if found.nil?
        @forecasts = {}
      else
        info_for(found).update
      end
    end
    self
  end

  private

    def info_for(gweather_location)
      @info = GWeather::Info.new(gweather_location)
      @info.set_property('application-id', APPLICATION_ID)
      @info.set_property('contact-info', CONTACT_INFO)
      @info.set_property('enabled-providers', GWeather::Provider::MET_NO)
      @info.signal_connect('updated') { on_info_updated }
      @info
    end

    def on_info_updated
      @forecasts = @info.forecast_list.each_with_object({}) do |forecast, hash|
        ok, unix_seconds = forecast.value_update
        if ok
          day = Time.at(unix_seconds).to_date
          hash[day] ||= [forecast.icon_name, forecast.temp_summary]
        end
      end
      @updated_handlers.each(&:call)
      self
    rescue StandardError
      self
    end

    # Upstream's gcal_weather_service: a named location only. See the class
    # comment for why "automatic" has nothing to ask in this port.
    def location
      name = @settings.weather_location_name
      if name.nil? || name.empty?
        nil
      else
        find_city(GWeather::Location.world, name.downcase)
      end
    end

    def find_city(location, name)
      child = location.next_child(nil)
      while child
        if child.level == :city && city_matches?(child, name)
          return child
        end

        found = find_city(child, name)
        return found if found

        child = location.next_child(child)
      end
      nil
    end

    def city_matches?(location, name)
      location.city_name&.downcase == name || location.name&.downcase == name
    end
end
