# frozen_string_literal: true

require_relative '../main'

module GnomeCalendar
  # Application is the gem's packaged entry point. The port itself lives in
  # the flat `lib/*.rb` files, with `App` (lib/main.rb) as the application;
  # this class exists so that `GnomeCalendar::Application.new.build.run`,
  # which the gemspec and the executable stub advertise, reaches it.
  class Application
    def initialize(**options)
      @options = options
    end

    def build = app.build

    def run(argv = []) = app.run(argv)

    def app = @app ||= App.new(**@options)
  end
end
