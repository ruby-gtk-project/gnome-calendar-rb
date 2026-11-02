# frozen_string_literal: true

require 'securerandom'
require 'time'
require 'adwaita'
require_relative 'date_time_utils'
require_relative 'range'
require_relative 'recurrence'
require_relative 'event_attendee'
require_relative 'event_organizer'
require_relative 'settings'

# Event is one entry on a calendar: when it happens, what it is called, who is
# coming, and which calendar it belongs to.
#
# Upstream's GcalEvent wraps an ECalComponent and writes every setter straight
# back into it. The port has no Evolution Data Server, so the event owns its
# own fields and serialises to the JSON the manager stores — but the API, the
# derived range, the multiday test, the sort order and the formatted date are
# the upstream ones.
#
# Ported from upstream's src/core/gcal-event.c.
#
class Event
  # Upstream's "calendar:uid" uuid format, used as the key everywhere a
  # widget has to find the event it is showing again.
  attr_reader :uid
  attr_accessor :calendar
  # The RECURRENCE-ID of a detached occurrence: nil for the series itself,
  # and the occurrence's start for every instance a view draws.
  attr_accessor :recurrence_id
  attr_reader :summary, :description, :location, :date_start, :date_end, :recurrence, :organizer

  def initialize(uid: nil, **attributes)
    @uid = uid || SecureRandom.uuid
    @calendar = attributes[:calendar]
    @summary = attributes.fetch(:summary, '').to_s
    @description = attributes.fetch(:description, '').to_s
    @location = attributes.fetch(:location, '').to_s
    @all_day = attributes.fetch(:all_day, false)
    @date_start = attributes.fetch(:date_start, Time.now)
    @date_end = attributes[:date_end]
    @color = attributes[:color]
    @recurrence = attributes[:recurrence]
    @organizer = attributes[:organizer]
    @attendees = attributes.fetch(:attendees, [])
    @alarms = attributes.fetch(:alarms, [])
    @recurrence_id = attributes[:recurrence_id]
  end

  # Upstream's gcal_event_new_from_event(): a detached copy, same values and
  # same uid, which is what the editor edits so a cancel changes nothing.
  def copy
    self.class.new(
      uid:         uid,
      calendar:    calendar,
      summary:     summary,
      description: description,
      location:    location,
      all_day:     all_day?,
      date_start:  date_start,
      date_end:    @date_end,
      color:       @color,
      recurrence:  recurrence&.copy,
      organizer:   organizer,
      attendees:   attendees.dup,
      alarms:      alarms.dup,
    )
  end

  # The uuid the views key their widgets on: upstream's
  # get_uuid_from_component().
  def uuid
    case recurrence_id
    when nil then "#{calendar&.id}:#{uid}"
    else "#{calendar&.id}:#{uid}:#{recurrence_id}"
    end
  end

  def summary=(value)
    @summary = value.to_s
    value
  end

  def description=(value)
    @description = value.to_s
    value
  end

  def location=(value)
    @location = value.to_s
    value
  end

  def all_day? = @all_day

  def all_day=(value)
    @all_day = value
    @range = nil
    value
  end

  def date_start=(value)
    @date_start = value
    @range = nil
    value
  end

  def date_end=(value)
    @date_end = value
    @range = nil
    value
  end

  # Upstream's gcal_event_get_date_end(): a missing end means the event ends
  # when it starts.
  def date_end = @date_end || @date_start

  def recurrence=(value)
    @recurrence = value
    value
  end

  # Upstream's gcal_event_has_recurrence().
  def recurrence? = !recurrence.nil? && recurrence.repeats?

  # Upstream's gcal_event_get_range(): all-day events compare by date, timed
  # events by instant.
  def range
    @range ||= begin
      range_type = CalendarRange::DEFAULT
      if all_day?
        range_type = CalendarRange::DATE_ONLY
      end
      CalendarRange.new(date_start, date_end, range_type)
    end
  end

  # Upstream's gcal_event_overlaps().
  def overlaps?(other_range) = range.overlap(other_range).first != CalendarRange::NO_OVERLAP

  # Upstream's gcal_event_is_multiday(): an all-day event spanning one day is
  # not multiday, and a timed event ending exactly at midnight belongs to the
  # day before, which is why the end is made inclusive first.
  def multiday?
    if all_day?
      DateTimeUtils.compare_date(date_end, date_start) > 1
    else
      DateTimeUtils.compare_date(date_end - 1, date_start).positive?
    end
  end

  # Upstream's gcal_event_get_color(): the event's own colour when it has
  # one, its calendar's otherwise.
  def color = @color || calendar&.color || Gdk::RGBA.parse('#3584e4')

  def color=(value)
    @color = value
    value
  end

  # Upstream's gcal_event_get_attendees(), as a plain list.
  def attendees = @attendees

  def add_attendee(attendee)
    @attendees << attendee
    attendee
  end

  def remove_attendee(attendee)
    @attendees.delete(attendee)
    self
  end

  def organizer=(value)
    @organizer = value
    value
  end

  # Alarms, as the minutes before the start at which they fire — the only
  # part of upstream's ECalComponentAlarm the reminders section exposes.
  def alarms = @alarms

  def alarms? = !@alarms.empty?

  def add_alarm(minutes)
    unless @alarms.include?(minutes)
      @alarms << minutes
      @alarms.sort!
    end
    self
  end

  def remove_alarm(minutes)
    @alarms.delete(minutes)
    self
  end

  def remove_all_alarms
    @alarms = []
    self
  end

  # Upstream's gcal_event_compare(): all-day events first, then by start,
  # then longest first.
  def compare(other)
    if all_day? != other.all_day?
      boolean_to_integer(other.all_day?) - boolean_to_integer(all_day?)
    else
      start_difference = date_start.to_i - other.date_start.to_i
      case start_difference
      when 0 then other.duration - duration
      else start_difference
      end
    end
  end

  def <=>(other) = compare(other)

  # Seconds between the start and the end, which is what the sort above
  # compares when two events start together.
  def duration = date_end.to_i - date_start.to_i

  # Upstream's gcal_event_schedule_equal().
  def schedule_equal?(other)
    recurrence? == other.recurrence? &&
      Recurrence.same?(recurrence, other.recurrence) &&
      all_day? == other.all_day? &&
      date_start.to_i == other.date_start.to_i &&
      date_end.to_i == other.date_end.to_i &&
      date_start.utc_offset == other.date_start.utc_offset &&
      date_end.utc_offset == other.date_end.utc_offset
  end

  # Upstream's gcal_event_strings_equal().
  def strings_equal?(other)
    summary == other.summary && description == other.description && location == other.location
  end

  # Upstream's gcal_event_alarms_equal().
  def alarms_equal?(other) = alarms.sort == other.alarms.sort

  # Upstream's gcal_event_format_date(): the four shapes a date range takes,
  # depending on whether the event is multiday and whether it is all-day.
  def format_date(time_format = Settings::FORMAT_24H)
    hour_format = '%R'
    if time_format == Settings::FORMAT_12H
      hour_format = '%I:%M %p'
    end

    start_date = date_start.strftime('%x')
    end_date = date_end.strftime('%x')

    if multiday?
      multiday_date_string(start_date, end_date, hour_format)
    elsif all_day?
      start_date
    else
      "#{start_date}, #{date_start.strftime(hour_format)} – #{date_end.strftime(hour_format)}"
    end
  end

  # The short time shown on an event widget: nothing for an all-day event,
  # the start time otherwise.
  def format_timestamp(time_format = Settings::FORMAT_24H)
    if all_day?
      ''
    elsif time_format == Settings::FORMAT_12H
      date_start.strftime('%I:%M %p')
    else
      date_start.strftime('%R')
    end
  end

  # The JSON the manager stores. Times are written as ISO8601 with their
  # offset so a reload keeps the zone the event was created in.
  def to_h
    {
      'uid'         => uid,
      'summary'     => summary,
      'description' => description,
      'location'    => location,
      'all-day'     => all_day?,
      'date-start'  => date_start.iso8601,
      'date-end'    => date_end.iso8601,
      'color'       => @color&.to_s,
      'rrule'       => recurrence&.to_rrule,
      'organizer'   => organizer&.to_property,
      'attendees'   => attendees.map(&:to_property),
      'alarms'      => alarms,
    }
  end

  # Rebuilds an event from `to_h`. The calendar is passed in rather than
  # stored, because the calendar owns the file the event was read from.
  def self.from_h(hash, calendar: nil)
    new(
      uid:         hash['uid'],
      calendar:    calendar,
      summary:     hash.fetch('summary', ''),
      description: hash.fetch('description', ''),
      location:    hash.fetch('location', ''),
      all_day:     hash.fetch('all-day', false),
      date_start:  Time.iso8601(hash.fetch('date-start')),
      date_end:    Time.iso8601(hash.fetch('date-end')),
      color:       parse_color(hash['color']),
      recurrence:  Recurrence.parse(hash['rrule']),
      organizer:   parse_organizer(hash['organizer']),
      attendees:   hash.fetch('attendees', []).map { |property| EventAttendee.parse(property) },
      alarms:      hash.fetch('alarms', []),
    )
  end

  def self.parse_color(value)
    case value
    when nil, '' then nil
    else Gdk::RGBA.parse(value)
    end
  end

  def self.parse_organizer(value)
    case value
    when nil, '' then nil
    else EventOrganizer.parse(value)
    end
  end

  def to_s = "#<Event #{uuid} #{summary.inspect} #{range}>"

  alias inspect to_s

  private

    def multiday_date_string(start_date, end_date, hour_format)
      if all_day?
        "#{start_date} – #{end_date}"
      else
        start_time = date_start.strftime(hour_format)
        end_time = date_end.strftime(hour_format)
        "#{start_date} #{start_time} – #{end_date} #{end_time}"
      end
    end

    def boolean_to_integer(value)
      case value
      when true then 1
      else 0
      end
    end
end
