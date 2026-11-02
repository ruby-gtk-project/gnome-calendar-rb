# frozen_string_literal: true

require 'securerandom'
require 'adwaita'

# Calendar is one source of events: its name, the colour its events are drawn
# in, whether it is read-only, and whether the user currently wants to see it.
#
# Upstream's GcalCalendar wraps an ESource and an ECalClient from Evolution
# Data Server. The port stores its calendars as files of its own (see
# Manager), so a calendar here is the metadata plus the path its events live
# in — the properties every widget binds to are the upstream ones.
#
# Ported from upstream's src/core/gcal-calendar.c.
#
class Calendar
  DEFAULT_COLOR = '#3584e4'

  attr_reader :id
  attr_accessor :name, :path

  def initialize(id: nil, name: '', **attributes)
    @id = id || SecureRandom.uuid
    @name = name.to_s
    @color = coerce_color(attributes.fetch(:color, DEFAULT_COLOR))
    @read_only = attributes.fetch(:read_only, false)
    @visible = attributes.fetch(:visible, true)
    @default = attributes.fetch(:default, false)
    @path = attributes[:path]
  end

  # Upstream's gcal_calendar_get_color() / set_color(). A string is accepted
  # as well as a Gdk::RGBA, because that is what the JSON holds.
  def color = @color

  def color=(value)
    @color = coerce_color(value)
    @color
  end

  # Upstream's gcal_calendar_is_read_only().
  def read_only? = @read_only

  def read_only=(value)
    @read_only = value
    value
  end

  # Upstream's gcal_calendar_get_visible() / set_visible(): whether the views
  # draw this calendar's events at all.
  def visible? = @visible

  def visible=(value)
    @visible = value
    value
  end

  # Whether new events land here by default — upstream keeps this on the
  # manager, but it belongs with the calendar it describes.
  def default? = @default

  def default=(value)
    @default = value
    value
  end

  def writable? = !read_only?

  def to_h
    {
      'id'        => id,
      'name'      => name,
      'color'     => color.to_s,
      'read-only' => read_only?,
      'visible'   => visible?,
      'default'   => default?,
    }
  end

  def self.from_h(hash)
    new(
      id:        hash['id'],
      name:      hash.fetch('name', ''),
      color:     hash.fetch('color', DEFAULT_COLOR),
      read_only: hash.fetch('read-only', false),
      visible:   hash.fetch('visible', true),
      default:   hash.fetch('default', false),
    )
  end

  def to_s = "#<Calendar #{id} #{name.inspect}>"

  alias inspect to_s

  private

    def coerce_color(value)
      case value
      when Gdk::RGBA then value
      when nil, '' then Gdk::RGBA.parse(DEFAULT_COLOR)
      else Gdk::RGBA.parse(value.to_s) || Gdk::RGBA.parse(DEFAULT_COLOR)
      end
    end
end
