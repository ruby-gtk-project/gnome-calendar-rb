# frozen_string_literal: true

require 'adwaita'

# Utils holds the free functions upstream keeps in src/utils/gcal-utils.c:
# weekday and month names, the first day of the week, workday detection, the
# colour paintables calendars are drawn with, and the handful of string
# manipulations the event editor and the importer share.
#
# Ported from upstream's src/utils/gcal-utils.c and src/utils/gcal-utils.h.
#
module Utils
  # Upstream's N_WEEKDAYS, MINUTES_PER_DAY and MAX_MINUTES.
  N_WEEKDAYS = 7
  MINUTES_PER_DAY = 1440
  MAX_MINUTES = N_WEEKDAYS * MINUTES_PER_DAY

  # Bit values of upstream's GcalWeekDay, indexed so that `1 << weekday` with
  # a 0-is-Sunday weekday hits the right bit.
  SUNDAY    = 1 << 0
  MONDAY    = 1 << 1
  TUESDAY   = 1 << 2
  WEDNESDAY = 1 << 3
  THURSDAY  = 1 << 4
  FRIDAY    = 1 << 5
  SATURDAY  = 1 << 6

  # Upstream's no_work_day_per_locale table, keyed by the territory part of
  # LC_TIME. Territories absent from the table rest on Saturday and Sunday.
  NO_WORK_DAYS_PER_TERRITORY = {
    'AE' => FRIDAY | SATURDAY,
    'AF' => FRIDAY | SATURDAY,
    'BD' => FRIDAY | SATURDAY,
    'BH' => FRIDAY | SATURDAY,
    'BN' => SUNDAY | FRIDAY,
    'CR' => SATURDAY,
    'DJ' => FRIDAY,
    'DZ' => FRIDAY | SATURDAY,
    'EG' => FRIDAY | SATURDAY,
    'GN' => SATURDAY,
    'HK' => SATURDAY,
    'IL' => FRIDAY | SATURDAY,
    'IQ' => FRIDAY | SATURDAY,
    'IR' => THURSDAY | FRIDAY,
    'KW' => FRIDAY | SATURDAY,
    'KZ' => FRIDAY | SATURDAY,
    'LY' => FRIDAY | SATURDAY,
    'MX' => SATURDAY,
    'MY' => FRIDAY | SATURDAY,
    'NP' => SATURDAY,
    'OM' => FRIDAY | SATURDAY,
    'QA' => FRIDAY | SATURDAY,
    'SA' => FRIDAY | SATURDAY,
    'SU' => FRIDAY | SATURDAY,
    'SY' => FRIDAY | SATURDAY,
    'UG' => SUNDAY,
    'YE' => FRIDAY | SATURDAY,
  }.freeze

  DEFAULT_NO_WORK_DAYS = SATURDAY | SUNDAY

  # Abbreviated weekday names, index 0 is Sunday — the order upstream's
  # nl_langinfo(ab_day[i]) returns.
  ABBREVIATED_WEEKDAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  # Single-letter grid abbreviations, from gcal-date-chooser.c's
  # calendar_get_weekday_name(). Index 0 is Sunday.
  GRID_WEEKDAYS = %w[S M T W T F S].freeze

  MONTH_NAMES = %w[
    January February March April May June
    July August September October November December
  ].freeze

  # The portal's week-start-day values, in the order upstream lists them, so
  # the index is the first weekday with 0 meaning Sunday.
  PORTAL_WEEKDAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

  # The service names upstream recognises in a URL, searched in order; the
  # first needle found in the URL wins.
  SERVICE_NAMES = [
    ['bluejeans', 'BlueJeans'],
    ['bigbluebutton', 'BigBlueButton'],
    ['bbb', 'BigBlueButton'],
    ['meet.google.com', 'Google Meet'],
    ['meet.jit.si', 'Jitsi'],
    ['jitsi', 'Jitsi'],
    ['meetings.dialpad.com', 'Uber Conference'],
    ['meet.gnome.com', 'GNOME Meet'],
    ['teams.microsoft.com', 'Microsoft Teams'],
    ['whereby.com', 'Whereby'],
    ['webex', 'Webex'],
    ['zoom.us', 'Zoom'],
    ['geo:', 'View Map'],
    ['openstreetmap.org', 'OpenStreetMap'],
    ['maps.app.goo.gl', 'Google Maps'],
    ['google.com/maps', 'Google Maps'],
    ['bing.com/maps', 'Bing Maps'],
  ].freeze

  module_function

  # Upstream's gcal_get_weekday(): the abbreviated name of weekday @index,
  # counting Sunday as 0.
  def weekday(index) = ABBREVIATED_WEEKDAYS[index % N_WEEKDAYS]

  # The one-letter grid abbreviation the date chooser's header row shows.
  def grid_weekday(index) = GRID_WEEKDAYS[index % N_WEEKDAYS]

  # Upstream's gcal_get_month_name(): January is 0.
  def month_name(index) = MONTH_NAMES[index % 12]

  # Upstream's get_first_weekday(): the portal's org.gnome.desktop.calendar
  # week-start-day setting when the portal answers, the locale's convention
  # otherwise. 0 is Sunday.
  def first_weekday
    @first_weekday ||= first_weekday_from_portal || first_weekday_from_locale
  end

  # Asks the settings portal for week-start-day. Returns nil when there is no
  # portal, no session bus, or an answer we do not recognise — which is how a
  # run outside a desktop session (a test, a tty, CI) falls through to the
  # locale.
  def first_weekday_from_portal
    proxy = Gio::DBusProxy.new(
      Gio::DBusConnection.new(:session),
      :none,
      nil,
      'org.freedesktop.portal.Desktop',
      '/org/freedesktop/portal/desktop',
      'org.freedesktop.portal.Settings',
    )
    answer = proxy.call_sync(
      'ReadOne',
      GLib::Variant.new(['org.gnome.desktop.calendar', 'week-start-day']),
      :none,
      -1,
    )
    PORTAL_WEEKDAYS.index(answer.get_child_value(0).value.to_s)
  rescue StandardError, NoMethodError
    nil
  end

  # The locale's first weekday. Territories that start the week on Sunday are
  # the exception rather than the rule in the C library's data, and Ruby gives
  # us no nl_langinfo, so the language/territory in LC_TIME decides.
  def first_weekday_from_locale
    territory = locale_territory
    case territory
    when 'US', 'CA', 'JP', 'IL', 'BR', 'MX', 'PH', 'KR', 'TW', 'ZA', 'AU', 'NZ' then 0
    else 1
    end
  end

  # The two-letter territory of LC_TIME (or LC_ALL/LANG), as upstream reads
  # out of setlocale(LC_TIME, NULL).
  def locale_territory
    locale = ENV['LC_TIME'] || ENV['LC_ALL'] || ENV.fetch('LANG', '')
    locale.to_s[3, 2].to_s.upcase
  end

  # Upstream's is_workday(): @day counts Sunday as 0.
  def workday?(day)
    case day
    when 0...N_WEEKDAYS
      no_work_days = NO_WORK_DAYS_PER_TERRITORY.fetch(locale_territory, DEFAULT_NO_WORK_DAYS)
      (no_work_days & (1 << day)).zero?
    else false
    end
  end

  # Upstream's gcal_get_paintable_from_color(): a @size × @size square of
  # @color.
  def paintable_from_color(color, size)
    Gtk::Snapshot.new.tap do |snapshot|
      snapshot.append_color(
        color,
        Graphene::Rect.new(
          0,
          0,
          size,
          size,
        ),
      )
    end.to_paintable(Graphene::Size.new(size, size))
  end

  # Upstream's get_circle_paintable_from_color(): the same square, clipped to
  # a circle.
  def circle_paintable_from_color(color, size)
    Gtk::Snapshot.new.tap do |snapshot|
      snapshot.push_rounded_clip(
        Gsk::RoundedRect.new.init_from_rect(
          Graphene::Rect.new(
            0,
            0,
            size,
            size,
          ),
          size / 2.0,
        ),
      )
      snapshot.append_color(
        color,
        Graphene::Rect.new(
          0,
          0,
          size,
          size,
        ),
      )
      snapshot.pop
    end.to_paintable(Graphene::Size.new(size, size))
  end

  # Upstream's gcal_is_valid_event_name().
  def valid_event_name?(name) = !name.to_s.strip.empty?

  # Upstream's gcal_get_service_name_from_url(): the display name of the
  # conferencing or map service the URL belongs to, or nil.
  def service_name_from_url(url)
    SERVICE_NAMES.find { |needle, _name| url.to_s.include?(needle) }&.last
  end

  # Upstream's gcal_get_email_from_mailto_uri(): the address out of
  # "mailto:someone@example.com". A URI that is not exactly scheme:address
  # comes back unchanged, as it does upstream.
  def email_from_mailto_uri(uri)
    pieces = uri.to_s.split(':')
    case pieces.length
    when 2 then pieces[1]
    else uri
    end
  end

  # Upstream's gcal_utils_format_filename_for_display(): drop the extension,
  # turn underscores into spaces, strip.
  def format_filename_for_display(filename)
    File.basename(filename.to_s).sub(/\.[^.]*\z/, '').tr('_', ' ').strip
  end

  # Upstream's GOOGLE_DELIMITER and TEAMS_DELIMITER: the horizontal rules
  # Google Calendar and Microsoft Teams wrap their generated meeting section
  # in when they add a video call to an event's description.
  GOOGLE_DELIMITER = '-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-'
  TEAMS_DELIMITER = '_' * 80

  # Upstream's gcal_utils_extract_meeting_url(): pulls a video-call URL out of
  # an event description generated by Google Calendar or Microsoft Teams, and
  # hands back the description with that generated section cut off.
  #
  # Returns [description, meeting_url], meeting_url nil when neither provider's
  # delimiter is found (or neither delimiter pair closes, or no URL is inside).
  def extract_meeting_url(description)
    extract_google_section(description) || extract_teams_section(description) || [description, nil]
  end

  # Upstream's gcal_utils_extract_google_section().
  def extract_google_section(description)
    delimited_section(description, GOOGLE_DELIMITER) do |section, before|
      url_start = section.index('https://meet.google.com')
      [before, google_url_at(section, url_start)]
    end
  end

  def google_url_at(section, url_start)
    if url_start.nil?
      nil
    else
      section[url_start, 'https://meet.google.com/xxx-xxxx-xxx'.length]
    end
  end

  # Upstream's gcal_utils_extract_teams_section().
  def extract_teams_section(description)
    delimited_section(description, TEAMS_DELIMITER) do |section, before|
      url_start = section.index('https://teams.microsoft.com')
      [before, teams_url_at(section, url_start)]
    end
  end

  def teams_url_at(section, url_start)
    if url_start.nil?
      nil
    else
      line_end = section.index("\n", url_start + 1)
      if line_end.nil?
        section[url_start..]
      else
        section[url_start...line_end]
      end
    end
  end

  # Shared by both extractors: finds the section between a delimiter's first
  # and second occurrence and hands it, plus the text before it, to the
  # block; nil when the delimiter does not open and close.
  def delimited_section(description, delimiter)
    if description.nil?
      nil
    else
      bounds = delimiter_bounds(description, delimiter)
      if bounds.nil?
        nil
      else
        yield(description[bounds[0]...bounds[1]], description[0, bounds[2]])
      end
    end
  end

  def delimiter_bounds(description, delimiter)
    first = description.index(delimiter)
    if first.nil?
      nil
    else
      section_start = first + delimiter.length
      last = description.index(delimiter, section_start)
      if last.nil?
        nil
      else
        [section_start, last, first]
      end
    end
  end

  # Upstream's format_utc_offset(): "+HHMM", or "+HHMMSS" when the offset is
  # not a whole minute. Accepts seconds or microseconds, as upstream does.
  def format_utc_offset(offset)
    sign = '+'
    if offset.negative?
      offset = -offset
      sign = '-'
    end

    if offset >= 1_000_000
      offset /= 1_000_000
    end

    hours = offset / 3600
    minutes = (offset % 3600) / 60
    seconds = offset % 60

    case seconds
    when 0 then format('%<sign>s%<hours>02d%<minutes>02d', sign: sign, hours: hours, minutes: minutes)
    else
      format(
        '%<sign>s%<hours>02d%<minutes>02d%<seconds>02d',
        sign:    sign,
        hours:   hours,
        minutes: minutes,
        seconds: seconds,
      )
    end
  end
end
