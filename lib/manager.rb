# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'calendar'
require_relative 'date_time_utils'
require_relative 'event'
require_relative 'global'
require_relative 'range'
require_relative 'range_tree'
require_relative 'recurrence'

# Manager owns the calendars and their events, and is the only thing in the
# app that writes them down. Every view asks it "what happens between these
# two instants?" and every editor hands it a created, updated or deleted
# event.
#
# Upstream talks to Evolution Data Server: calendars are ESources, events are
# ECalComponents, and a calendar monitor streams them in per range. The port
# has no EDS, so each calendar is a JSON file under XDG_DATA_HOME and the
# whole set is held in memory, indexed by a range tree — the queries, the
# recurrence expansion and the signals are the upstream ones.
#
# Ported from upstream's src/core/gcal-manager.c and
# src/core/gcal-calendar-monitor.c.
#
class Manager
  # How far a recurring event is expanded past the end of a queried range,
  # so a weekly event still shows up in a month the user scrolls to.
  MAX_RECURRENCES = 1000

  def initialize(data_dir: nil)
    @data_dir = data_dir || default_data_dir
    @calendars = []
    @events = {}
    @tree = RangeTree.new
    @handlers = {
      calendar_added:   [],
      calendar_changed: [],
      calendar_removed: [],
      events_changed:   [],
      synchronizing:    [],
    }
    @synchronizing = false
  end

  attr_reader :data_dir

  # Upstream's gcal_manager_startup(): read what is on disk, and make sure
  # there is at least one calendar to put an event in.
  def startup
    raise 'Manager#startup must run on the main thread' unless Global.main_thread?

    load_calendars
    if @calendars.empty?
      create_calendar(name: 'Personal', color: Calendar::DEFAULT_COLOR, default: true)
    end
    @calendars.each { |calendar| notify(:calendar_added, calendar) }
    notify(:events_changed, nil)
    self
  end

  # Upstream's gcal_manager_get_calendars().
  def calendars = @calendars.dup

  def visible_calendars = @calendars.select(&:visible?)

  def writable_calendars = @calendars.select(&:writable?)

  def calendar(id) = @calendars.find { |calendar| calendar.id == id }

  # Upstream's gcal_manager_get_default_calendar(): the calendar marked
  # default, or the first writable one.
  def default_calendar
    @calendars.find(&:default?) || writable_calendars.first || @calendars.first
  end

  # Upstream's gcal_manager_set_default_calendar().
  def default_calendar=(calendar)
    @calendars.each { |existing| existing.default = existing.equal?(calendar) }
    save_calendars
    notify(:calendar_changed, calendar)
    calendar
  end

  # Upstream's gcal_manager_add_source(), with the port's own storage in
  # place of an ESource and a backend name.
  def create_calendar(name:, color: Calendar::DEFAULT_COLOR, default: false)
    Calendar.new(name: name, color: color, default: default).tap do |calendar|
      calendar.path = File.join(@data_dir, "#{calendar.id}.json")
      @calendars << calendar
      save_calendar(calendar)
      save_calendars
      notify(:calendar_added, calendar)
    end
  end

  # Upstream's gcal_manager_save_source(): the metadata changed, write it
  # back and tell the sidebar.
  def save_calendar_metadata(calendar)
    save_calendars
    notify(:calendar_changed, calendar)
    calendar
  end

  def remove_calendar(calendar)
    @calendars.delete(calendar)
    events_of(calendar).each { |event| forget_event(event) }
    if calendar.path && File.exist?(calendar.path)
      File.delete(calendar.path)
    end
    save_calendars
    notify(:calendar_removed, calendar)
    notify(:events_changed, nil)
    self
  end

  # Toggling a calendar's visibility changes what every view draws, so it
  # notifies on both channels.
  def set_calendar_visible(calendar, visible)
    calendar.visible = visible
    save_calendars
    notify(:calendar_changed, calendar)
    notify(:events_changed, nil)
    self
  end

  # Upstream's gcal_manager_create_event().
  def create_event(event)
    event.calendar ||= default_calendar
    remember_event(event)
    save_calendar(event.calendar)
    notify(:events_changed, event)
    event
  end

  # Upstream's gcal_manager_update_event(). The modification type matters
  # once an event recurs: THIS_ONLY detaches the one occurrence, everything
  # else rewrites the series.
  def update_event(event, mod = Recurrence::MOD_ALL)
    forget_event(event)
    if mod == Recurrence::MOD_THIS_ONLY
      event.recurrence = nil
    end
    remember_event(event)
    save_calendar(event.calendar)
    notify(:events_changed, event)
    event
  end

  # Upstream's gcal_manager_remove_event().
  def remove_event(event, _mod = Recurrence::MOD_ALL)
    forget_event(event)
    save_calendar(event.calendar)
    notify(:events_changed, event)
    event
  end

  # Upstream's gcal_manager_move_event_to_source().
  def move_event_to_calendar(event, calendar)
    source = event.calendar
    forget_event(event)
    event.calendar = calendar
    remember_event(event)
    save_calendar(source)
    save_calendar(calendar)
    notify(:events_changed, event)
    event
  end

  def event(uuid) = @events[uuid]

  # Every event of every visible calendar overlapping @range, recurrences
  # expanded, in upstream's sort order. This is what a view asks for.
  def events_in_range(range)
    stored = @tree.data_at_range(range)
                  .reject(&:recurrence?)
                  .select { |event| event.calendar&.visible? }
    recurring = @events.values.select { |event| event.recurrence? && event.calendar&.visible? }
    occurrences = recurring.flat_map { |event| expand_recurrence(event, range) }
    (stored + occurrences).uniq(&:uuid).select { |event| event.overlaps?(range) }
                          .sort { |first, second| first.compare(second) }
  end

  # The events of @calendar, whether or not it is visible.
  def events_of(calendar) = @events.values.select { |event| event.calendar&.id == calendar.id }

  # Upstream's gcal_manager_get_synchronizing().
  def synchronizing? = @synchronizing

  # Upstream's gcal_manager_refresh(): re-reads every calendar from its
  # backing store. With local files that is quick, but it goes through the
  # same synchronizing signal so the sync indicator behaves as upstream's.
  def refresh
    raise 'Manager#refresh must run on the main thread' unless Global.main_thread?

    @synchronizing = true
    notify(:synchronizing, true)
    load_calendars
    @synchronizing = false
    notify(:synchronizing, false)
    notify(:events_changed, nil)
    self
  end

  # The signals upstream declares on GcalManager, each taking a block.
  def on_calendar_added(&block) = register(:calendar_added, block)

  def on_calendar_changed(&block) = register(:calendar_changed, block)

  def on_calendar_removed(&block) = register(:calendar_removed, block)

  def on_events_changed(&block) = register(:events_changed, block)

  def on_synchronizing(&block) = register(:synchronizing, block)

  private

    def register(signal, block)
      @handlers.fetch(signal) << block
      block
    end

    def notify(signal, payload)
      @handlers.fetch(signal).each { |handler| handler.call(payload) }
      self
    end

    def default_data_dir
      base = ENV['XDG_DATA_HOME'] || File.join(Dir.home, '.local', 'share')
      File.join(base, 'gnome-calendar-rb', 'calendars')
    end

    def index_path = File.join(@data_dir, 'calendars.json')

    def remember_event(event)
      @events[event.uuid] = event
      @tree.add_range(event.range, event)
      event
    end

    def forget_event(event)
      @events.delete(event.uuid)
      @tree.remove_data(event)
      event
    end

    # Reads the index of calendars, then each calendar's events.
    def load_calendars
      @calendars = read_index.map { |hash| Calendar.from_h(hash) }
      @calendars.each { |calendar| calendar.path = File.join(@data_dir, "#{calendar.id}.json") }
      @events = {}
      @tree.clear
      @calendars.each { |calendar| load_events(calendar) }
      self
    end

    def read_index
      JSON.parse(File.read(index_path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save_calendars
      write_json(index_path, @calendars.map(&:to_h))
      self
    end

    def load_events(calendar)
      read_events(calendar).each do |hash|
        remember_event(Event.from_h(hash, calendar: calendar))
      end
      self
    end

    def read_events(calendar)
      JSON.parse(File.read(calendar.path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save_calendar(calendar)
      case calendar
      when nil then self
      else write_json(calendar.path, events_of(calendar).map(&:to_h))
      end
    end

    def write_json(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(payload)}\n")
      self
    rescue SystemCallError
      self
    end

    # Walks a recurring event forward from its start, emitting a detached
    # copy for every occurrence that falls inside @range. The copies carry
    # the series' uid with the occurrence date appended, which is how a view
    # tells two occurrences of one event apart.
    def expand_recurrence(event, range)
      [].tap do |occurrences|
        current = event.date_start
        duration = event.duration
        count = 0

        while count < recurrence_limit(event) && current <= range.range_end
          occurrence = occurrence_at(event, current, duration)
          if occurrence.overlaps?(range)
            occurrences << occurrence
          end

          current = next_occurrence(event, current)
          count += 1
          if past_limit?(event, current)
            break
          end
        end
      end
    end

    def recurrence_limit(event)
      case event.recurrence.limit_type
      when Recurrence::COUNT then [event.recurrence.count, MAX_RECURRENCES].min
      else MAX_RECURRENCES
      end
    end

    def past_limit?(event, current)
      case event.recurrence.limit_type
      when Recurrence::UNTIL then current > event.recurrence.until
      else false
      end
    end

    # One occurrence as its own event, sharing everything but the dates.
    def occurrence_at(event, start, duration)
      event.copy.tap do |occurrence|
        occurrence.date_start = start
        occurrence.date_end = start + duration
        occurrence.recurrence = nil
        occurrence.recurrence_id = start.strftime('%Y%m%dT%H%M%S')
      end
    end

    # The next instant the rule fires at. MON_FRI steps a day at a time and
    # skips the weekend, which is what makes it distinct from WEEKLY.
    def next_occurrence(event, current)
      case event.recurrence.frequency
      when Recurrence::DAILY then DateTimeUtils.add_days(current, 1)
      when Recurrence::MON_FRI then next_weekday(current)
      when Recurrence::WEEKLY then DateTimeUtils.add_weeks(current, 1)
      when Recurrence::MONTHLY then DateTimeUtils.add_months(current, 1)
      when Recurrence::YEARLY then DateTimeUtils.add_months(current, 12)
      else DateTimeUtils.add_days(current, 1)
      end
    end

    def next_weekday(current)
      DateTimeUtils.add_days(current, 1).then do |candidate|
        case candidate.wday
        when 0, 6 then next_weekday(candidate)
        else candidate
        end
      end
    end
end
