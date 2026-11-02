# frozen_string_literal: true

require 'date'
require_relative 'utils'

# DateTimeUtils holds the date arithmetic the whole app leans on: where a week
# starts and ends, how two date-times compare when only their dates matter,
# and the "floating" minute arithmetic the schedule section needs so that
# 02:30 + 30 minutes is 03:00 even across a daylight-saving boundary.
#
# Upstream works in GDateTime; the port works in Ruby's Time, which carries
# the same zone-aware instant and formats with the same strftime.
#
# Ported from upstream's src/utils/gcal-date-time-utils.c.
#
module DateTimeUtils
  module_function

  # Upstream's gcal_date_time_get_days_in_month().
  def days_in_month(date) = Date.new(date.year, date.month, -1).day

  # Upstream's gcal_date_time_get_start_of_week(): midnight on the first day
  # of the week @date falls in, inclusive.
  def start_of_week(date)
    weekday = date.wday % Utils::N_WEEKDAYS
    days_after_week_start = (Utils::N_WEEKDAYS + weekday - Utils.first_weekday) % Utils::N_WEEKDAYS
    start_of_day(date - (days_after_week_start * 86_400))
  end

  # Upstream's gcal_date_time_get_end_of_week(): the exclusive end of the
  # week, which is the start of the next one.
  def end_of_week(date) = add_days(start_of_week(date), Utils::N_WEEKDAYS)

  # Midnight local time on @date's day.
  def start_of_day(date) = Time.new(
    date.year,
    date.month,
    date.day,
    0,
    0,
    0,
  )

  # Calendar-day arithmetic: adding 86_400 seconds crosses a DST boundary an
  # hour short, so the day is recomputed from the Y/M/D instead.
  def add_days(date, days)
    shifted = Date.new(date.year, date.month, date.day) + days
    Time.new(
      shifted.year,
      shifted.month,
      shifted.day,
      date.hour,
      date.min,
      date.sec,
    )
  end

  def add_weeks(date, weeks) = add_days(date, weeks * Utils::N_WEEKDAYS)

  # Calendar-month arithmetic, clamping the day to the length of the target
  # month so that 31 January + 1 month is 28 February.
  def add_months(date, months)
    shifted = Date.new(date.year, date.month, 1) >> months
    day = [date.day, Date.new(shifted.year, shifted.month, -1).day].min
    Time.new(
      shifted.year,
      shifted.month,
      day,
      date.hour,
      date.min,
      date.sec,
    )
  end

  # Upstream's gcal_date_time_compare_date(): negative, zero or positive by
  # date alone, with a nil sorting before anything.
  def compare_date(date1, date2)
    if date1.nil? && date2.nil?
      0
    elsif date1.nil?
      -1
    elsif date2.nil?
      1
    else
      (Date.new(date1.year, date1.month, date1.day) - Date.new(date2.year, date2.month, date2.day)).to_i
    end
  end

  def same_date?(date1, date2) = compare_date(date1, date2).zero?

  # Upstream's gcal_date_time_is_date(): a pure date has no time of day.
  def date?(date) = date.hour.zero? && date.min.zero? && date.sec.zero?

  # Upstream's date_time_to_date_timestamp(): YYYYMMDD as an integer, which
  # is what date-only ranges compare on.
  def date_timestamp(date) = (date.year * 10_000) + (date.month * 100) + date.day

  # Upstream's gcal_date_time_add_floating_minutes(): add the minutes, then
  # undo whatever the UTC offset did, so wall-clock arithmetic stays exact
  # across a daylight-saving change.
  def add_floating_minutes(initial, minutes)
    result = initial + (minutes * 60)
    result + (initial.utc_offset - result.utc_offset)
  end

  # Upstream's gcal_date_time_format_utc_offset(): "UTC", "UTC+2",
  # "UTC-5:30".
  def format_utc_offset(date)
    offset = date.utc_offset
    case offset
    when 0 then 'UTC'
    else
      sign = '+'
      if offset.negative?
        sign = '-'
        offset = -offset
      end

      hours = offset / 3600
      minutes = (offset - (hours * 3600)) / 60
      case minutes
      when 0 then "UTC#{sign}#{hours}"
      else format('UTC%<sign>s%<hours>d:%<minutes>02d', sign: sign, hours: hours, minutes: minutes)
      end
    end
  end

  # The ISO week number, as g_date_time_get_week_of_year() reports it.
  def week_of_year(date) = Date.new(date.year, date.month, date.day).cweek

  def week_year(date) = Date.new(date.year, date.month, date.day).cwyear
end
