# frozen_string_literal: true

require 'time'
require_relative 'date_time_utils'

# Recurrence is the repeat rule of an event, reduced to the handful of
# patterns the editor offers: no repeat, every day, Monday to Friday, every
# week, every month, every year — plus "other" for a rule the editor cannot
# express and must leave alone.
#
# Upstream reads and writes the rule through libical's ICalRecurrence; the
# port reads and writes the RRULE line itself, which is the same information
# in its on-the-wire form.
#
# Ported from upstream's src/core/gcal-recurrence.c.
#
class Recurrence
  # Upstream's GcalRecurrenceFrequency.
  NO_REPEAT = :no_repeat
  DAILY     = :daily
  MON_FRI   = :mon_fri
  WEEKLY    = :weekly
  MONTHLY   = :monthly
  YEARLY    = :yearly
  OTHER     = :other

  # Upstream's GcalRecurrenceLimitType.
  FOREVER = :forever
  COUNT   = :count
  UNTIL   = :until

  # Upstream's GcalRecurrenceModType: which instances an edit applies to.
  MOD_NONE            = :none
  MOD_THIS_ONLY       = :this_only
  MOD_THIS_AND_FUTURE = :this_and_future
  MOD_ALL             = :all

  # The FREQ value each frequency maps to, and back.
  FREQUENCIES = {
    DAILY   => 'DAILY',
    MON_FRI => 'WEEKLY',
    WEEKLY  => 'WEEKLY',
    MONTHLY => 'MONTHLY',
    YEARLY  => 'YEARLY',
  }.freeze

  WEEKDAY_RULE = %w[MO TU WE TH FR].freeze

  attr_accessor :frequency, :limit_type, :count
  attr_reader :until

  def initialize(frequency: NO_REPEAT, limit_type: FOREVER, count: 0, until_date: nil)
    @frequency = frequency
    @limit_type = limit_type
    @count = count
    @until = until_date
  end

  def until=(value)
    @until = value
    @limit_type = UNTIL
    value
  end

  # Upstream's gcal_recurrence_copy().
  def copy
    self.class.new(
      frequency:  frequency,
      limit_type: limit_type,
      count:      count,
      until_date: self.until,
    )
  end

  # Upstream's gcal_recurrence_is_equal(): two nils are equal, and a nil is
  # equal to nothing else. Named `same?` so it does not shadow `equal?`.
  def self.same?(recurrence1, recurrence2)
    if recurrence1.nil? && recurrence2.nil?
      true
    elsif recurrence1.nil? || recurrence2.nil?
      false
    else
      recurrence1.equal_to?(recurrence2)
    end
  end

  def equal_to?(other)
    frequency == other.frequency &&
      limit_type == other.limit_type &&
      same_limit?(other)
  end

  def repeats? = frequency != NO_REPEAT

  # Upstream's gcal_recurrence_parse_recurrence_rules(), reading the RRULE
  # line rather than the parsed ICalRecurrence. Returns nil when there is no
  # rule, exactly as upstream returns NULL for a component without
  # recurrences.
  def self.parse(rrule)
    parts = rule_parts(rrule)
    if parts.empty?
      nil
    else
      new(
        frequency:  frequency_from(parts),
        limit_type: FOREVER,
      ).tap { |recurrence| recurrence.apply_limit_from(parts) }
    end
  end

  # The RRULE value's "KEY=VALUE;KEY=VALUE" payload as a hash, with the
  # "RRULE:" prefix and any surrounding whitespace tolerated.
  def self.rule_parts(rrule)
    rrule.to_s.strip.sub(/\ARRULE[:;]/i, '').split(';').filter_map do |piece|
      key, value = piece.split('=', 2)
      case value
      when nil then nil
      else [key.to_s.upcase, value]
      end
    end.to_h
  end

  # Upstream's switch over the FREQ, including the BYDAY=MO,TU,WE,TH,FR test
  # that distinguishes "Monday – Friday" from a plain weekly repeat.
  def self.frequency_from(parts)
    case parts['FREQ'].to_s.upcase
    when 'DAILY' then DAILY
    when 'WEEKLY' then weekly_frequency_from(parts)
    when 'MONTHLY' then MONTHLY
    when 'YEARLY' then YEARLY
    else OTHER
    end
  end

  def self.weekly_frequency_from(parts)
    days = parts.fetch('BYDAY', '').to_s.upcase.split(',').map(&:strip)
    case days
    when WEEKDAY_RULE then MON_FRI
    else WEEKLY
    end
  end

  # COUNT wins over UNTIL, as it does upstream.
  def apply_limit_from(parts)
    count_value = parts.fetch('COUNT', '0').to_i
    if count_value.positive?
      @limit_type = COUNT
      @count = count_value
    else
      apply_until_from(parts['UNTIL'])
    end
  end

  # Upstream's gcal_recurrence_to_rrule(), as the RRULE value. A rule the
  # editor cannot express, and a non-repeating event, have no RRULE at all.
  def to_rrule
    case frequency
    when NO_REPEAT, OTHER then nil
    else
      pieces = ["FREQ=#{FREQUENCIES.fetch(frequency)}"]
      if frequency == MON_FRI
        pieces << "BYDAY=#{WEEKDAY_RULE.join(',')}"
      end
      pieces.concat(limit_pieces)
      pieces.join(';')
    end
  end

  def to_s = to_rrule.to_s

  private

    def apply_until_from(value)
      parsed = parse_until(value)
      case parsed
      when nil then @limit_type = FOREVER
      else
        @limit_type = UNTIL
        @until = parsed
      end
    end

    # An UNTIL is either a UTC instant ("20250131T235959Z") or a bare date
    # ("20250131"); anything else is treated as no limit, which is how
    # upstream handles a zero year.
    def parse_until(value)
      case value.to_s
      when /\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?\z/
        Time.utc(
          Regexp.last_match(1).to_i,
          Regexp.last_match(2).to_i,
          Regexp.last_match(3).to_i,
          Regexp.last_match(4).to_i,
          Regexp.last_match(5).to_i,
          Regexp.last_match(6).to_i,
        ).getlocal
      when /\A(\d{4})(\d{2})(\d{2})\z/
        Time.new(
          Regexp.last_match(1).to_i,
          Regexp.last_match(2).to_i,
          Regexp.last_match(3).to_i,
          0,
          0,
          0,
        )
      end
    end

    def limit_pieces
      case limit_type
      when COUNT then ["COUNT=#{count}"]
      when UNTIL then ["UNTIL=#{self.until.getutc.strftime('%Y%m%dT%H%M%SZ')}"]
      else []
      end
    end

    def same_limit?(other)
      case limit_type
      when COUNT then count == other.count
      when UNTIL then DateTimeUtils.compare_date(self.until, other.until).zero?
      else true
      end
    end
end
