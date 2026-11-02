# frozen_string_literal: true

require 'time'
require_relative 'date_time_utils'

# CalendarRange is a half-open span of time, [start, end). It is the unit the
# timeline, the range tree and every view agree on, and the whole point of it
# is `overlap`: the eleven ways two spans can sit relative to one another,
# reduced to an overlap kind plus the position of the first relative to the
# second.
#
# A date-only range ignores times; when either side of a comparison is
# date-only, both are compared as YYYYMMDD integers.
#
# Named CalendarRange rather than Range because Range is Ruby's own.
#
# Ported from upstream's src/core/gcal-range.c.
#
class CalendarRange
  # Upstream's GcalRangeOverlap.
  NO_OVERLAP = :no_overlap
  INTERSECTS = :intersects
  SUBSET     = :subset
  EQUAL      = :equal
  SUPERSET   = :superset

  # Upstream's GcalRangePosition.
  BEFORE = -1
  MATCH  = 0
  AFTER  = 1

  # Upstream's GcalRangeType.
  DEFAULT   = :default
  DATE_ONLY = :date_only

  attr_reader :range_start, :range_end, :range_type

  def initialize(range_start, range_end, range_type = DEFAULT)
    if range_start > range_end
      raise ArgumentError, 'range start must not be after range end'
    end

    @range_start = range_start
    @range_end = range_end
    @range_type = range_type
  end

  # Upstream's gcal_range_copy().
  def copy = self.class.new(range_start, range_end, range_type)

  def date_only? = range_type == DATE_ONLY

  # The timestamps a comparison against @other should use: unix seconds
  # normally, YYYYMMDD when either range is date-only. Upstream's
  # get_start_and_end_timestamps().
  def timestamps_against(other)
    if date_only? || other.date_only?
      [DateTimeUtils.date_timestamp(range_start), DateTimeUtils.date_timestamp(range_end)]
    else
      [range_start.to_i, range_end.to_i]
    end
  end

  # Upstream's gcal_range_calculate_overlap(): returns [overlap, position],
  # where the position is always that of `self` relative to @other.
  def overlap(other)
    start_a, end_a = timestamps_against(other)
    start_b, end_b = other.timestamps_against(self)

    start_diff = start_a - start_b
    end_diff = end_a - end_b

    if start_diff.zero? && end_diff.zero?
      [EQUAL, MATCH]
    elsif start_diff.zero?
      overlap_with_shared_start(end_diff)
    elsif end_diff.zero?
      overlap_with_shared_end(start_diff, start_a - end_b, end_a - start_b)
    else
      overlap_with_distinct_bounds(
        start_diff,
        end_diff,
        start_a - end_b,
        end_a - start_b,
      )
    end
  end

  # Upstream's gcal_range_compare(): -1, 0 or 1, by start then by end.
  def compare(other)
    start_a, end_a = timestamps_against(other)
    start_b, end_b = other.timestamps_against(self)

    result = start_a - start_b
    if result.zero?
      result = end_a - end_b
    end

    if result.negative?
      BEFORE
    elsif result.positive?
      AFTER
    else
      MATCH
    end
  end

  def <=>(other) = compare(other)

  def ==(other) = other.is_a?(CalendarRange) && overlap(other).first == EQUAL

  alias eql? ==

  def hash = [range_start.to_i, range_end.to_i, range_type].hash

  # Upstream's gcal_range_union().
  def union(other)
    start_a, end_a = timestamps_against(other)
    start_b, end_b = other.timestamps_against(self)

    start = other.range_start
    if start_a < start_b
      start = range_start
    end

    finish = other.range_end
    if end_a > end_b
      finish = range_end
    end

    union_type = DEFAULT
    if date_only? || other.date_only?
      union_type = DATE_ONLY
    end

    self.class.new(start, finish, union_type)
  end

  # Upstream's gcal_range_contains_datetime(). Default ranges are half-open;
  # date-only ranges include their last day, as upstream's switch does.
  def contains?(datetime)
    case range_type
    when DATE_ONLY
      timestamp = DateTimeUtils.date_timestamp(datetime)
      timestamp >= DateTimeUtils.date_timestamp(range_start) &&
        timestamp <= DateTimeUtils.date_timestamp(range_end)
    else
      timestamp = datetime.to_i
      timestamp >= range_start.to_i && timestamp < range_end.to_i
    end
  end

  # Upstream's gcal_range_to_string(): ISO8601 bounds, for debugging.
  def to_s = "[#{range_start.iso8601} | #{range_end.iso8601})"

  def inspect = "#<CalendarRange #{self} #{range_type}>"

  private

    # Cases 2.i and 3.i: the ranges start together.
    def overlap_with_shared_start(end_diff)
      if end_diff.positive?
        [SUPERSET, AFTER]
      else
        [SUBSET, BEFORE]
      end
    end

    # Cases 2.iii, 3.iii and the zero-length no-overlap cases: the ranges end
    # together.
    def overlap_with_shared_end(start_diff, a_start_b_end, a_end_b_start)
      if a_start_b_end >= 0
        [NO_OVERLAP, AFTER]
      elsif a_end_b_start <= 0
        [NO_OVERLAP, BEFORE]
      elsif start_diff.negative?
        [SUPERSET, BEFORE]
      else
        [SUBSET, AFTER]
      end
    end

    # Everything else: containment, no overlap, or a true intersection.
    def overlap_with_distinct_bounds(start_diff, end_diff, a_start_b_end, a_end_b_start)
      if start_diff.negative? && end_diff.positive?
        [SUPERSET, BEFORE]
      elsif start_diff.positive? && end_diff.negative?
        [SUBSET, AFTER]
      elsif a_start_b_end >= 0
        [NO_OVERLAP, AFTER]
      elsif a_end_b_start <= 0
        [NO_OVERLAP, BEFORE]
      elsif start_diff.negative?
        [INTERSECTS, BEFORE]
      else
        [INTERSECTS, AFTER]
      end
    end
end
