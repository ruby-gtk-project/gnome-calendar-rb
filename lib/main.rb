# frozen_string_literal: true

require 'adwaita'
require 'ashpd'
require_relative 'context'
require_relative 'date_time_utils'
require_relative 'shortcuts_dialog'
require_relative 'style'
require_relative 'window'

# App is the application: it owns the context every widget is handed, the app
# actions and their accelerators, the About dialog, and the window.
#
# Upstream subclasses AdwApplication; the Ruby bindings want a composed
# Gtk::Application, so the application object is held rather than inherited —
# everything else about it is upstream's.
#
# Ported from upstream's src/gui/gcal-application.c.
#
class App
  APP_ID = 'org.gnome.CalendarRb'
  UPSTREAM_URI = 'https://gitlab.gnome.org/GNOME/gnome-calendar'

  # Upstream's app actions and the accelerators it binds them to.
  APP_ACCELERATORS = {
    'app.shortcuts' => ['<Control>question'],
    'app.quit'      => ['<Control>q'],
  }.freeze

  # app_id and flags are injectable so a test can register a throwaway
  # application rather than the session's real one, and present: false builds
  # the whole widget tree without ever mapping the window.
  def initialize(**options)
    @app_id = options.fetch(:app_id, APP_ID)
    @flags = options.fetch(:flags, :default_flags)
    @present = options.fetch(:present, true)
    @context = options.fetch(:context, nil)
    @startup_date = options.fetch(:startup_date, nil)
  end

  def build
    app.tap do |application|
      application.signal_connect('startup') do
        Adwaita.init
        Style.install
        sync_color_scheme
        context.startup
      end

      application.signal_connect('activate') do
        window.build

        unless @startup_date.nil?
          window.active_date = @startup_date
        end

        install_actions

        if @present
          window.present
        end
      end
    end
  end

  def run(argv = []) = build.run(argv)

  # Adwaita::Application is unreliable in the Ruby bindings; the application
  # object comes from Gtk and only the window is Adwaita.
  def app = @app ||= Gtk::Application.new(@app_id, @flags)

  def context = @context ||= Context.new

  # Upstream's --date / --uuid land here: the date the window opens on.
  def startup_date=(date)
    @startup_date = date
    date
  end

  def window = @window ||= Window.new(app, context)

  def shortcuts_dialog = @shortcuts_dialog ||= ShortcutsDialog.new

  # Upstream's AdwAboutDialog, built from the same metadata its appdata
  # carries.
  def about_dialog
    @about_dialog ||= Adwaita::AboutDialog.new.tap do |dialog|
      dialog.application_name = 'Calendar'
      dialog.application_icon = 'x-office-calendar'
      dialog.developer_name = 'The GNOME Project'
      dialog.version = '1.0'
      dialog.website = UPSTREAM_URI
      dialog.issue_url = "#{UPSTREAM_URI}/-/issues"
      dialog.copyright = '© 2012 The Calendar authors'
      dialog.license_type = Gtk::License::GPL_3_0
      dialog.comments = 'Manage your calendars and events'
    end
  end

  private

    # Upstream's AdwStyleManager follows the desktop automatically once a
    # libadwaita app is running inside a session that offers it, but a
    # sandboxed app only ever sees the desktop's preference through the
    # settings portal's org.freedesktop.appearance namespace, which is what
    # this asks ashpd for. Outside a desktop session (this port's tests, a
    # tty, a container with no xdg-desktop-portal running) the portal call
    # raises and the style manager is left on whatever Adwaita.init chose.
    def sync_color_scheme
      case Ashpd::Settings.color_scheme.to_s
      when /prefer_dark|prefer-dark/ then Adwaita::StyleManager.default.color_scheme = Adwaita::ColorScheme::PREFER_DARK
      when /prefer_light|prefer-light/ then Adwaita::StyleManager.default.color_scheme = Adwaita::ColorScheme::PREFER_LIGHT
      else Adwaita::StyleManager.default.color_scheme = Adwaita::ColorScheme::DEFAULT
      end
      self
    rescue StandardError, NoMethodError
      self
    end

    # Upstream's gcal_application_class_init() action entries.
    def install_actions
      {
        'sync'      => -> { context.manager.refresh },
        'about'     => -> { about_dialog.present(window.window) },
        'shortcuts' => -> { shortcuts_dialog.present(window.window) },
        'quit'      => -> { app.quit },
      }.each do |name, callback|
        app.add_action(
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect('activate') { callback.call }
          end,
        )
      end

      APP_ACCELERATORS.each { |action, accelerators| app.set_accels_for_action(action, accelerators) }
      self
    end
end
