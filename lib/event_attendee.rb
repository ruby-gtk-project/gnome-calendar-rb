# frozen_string_literal: true

require_relative 'utils'

# EventAttendee is one ATTENDEE of an event: who they are, what they are
# (a person, a room, a piece of equipment), what part they play, and whether
# they have answered yet.
#
# Upstream wraps an ECalComponentAttendee; the port holds the same iCalendar
# fields and parses them from, and writes them back to, the ATTENDEE property
# parameters.
#
# Ported from upstream's src/core/gcal-event-attendee.c.
#
class EventAttendee
  # Upstream's GcalEventAttendeeType.
  INDIVIDUAL = :individual
  GROUP      = :group
  RESOURCE   = :resource
  ROOM       = :room
  UNKNOWN    = :unknown
  TYPE_NONE  = :none

  TYPES = {
    'INDIVIDUAL' => INDIVIDUAL,
    'GROUP'      => GROUP,
    'RESOURCE'   => RESOURCE,
    'ROOM'       => ROOM,
    'UNKNOWN'    => UNKNOWN,
  }.freeze

  # Upstream's GcalEventAttendeePartStat.
  NEEDS_ACTION = :needs_action
  ACCEPTED     = :accepted
  DECLINED     = :declined
  TENTATIVE    = :tentative
  DELEGATED    = :delegated
  COMPLETED    = :completed
  IN_PROCESS   = :in_process
  FAILED       = :failed
  PART_NONE    = :none

  PART_STATUSES = {
    'NEEDS-ACTION' => NEEDS_ACTION,
    'ACCEPTED'     => ACCEPTED,
    'DECLINED'     => DECLINED,
    'TENTATIVE'    => TENTATIVE,
    'DELEGATED'    => DELEGATED,
    'COMPLETED'    => COMPLETED,
    'IN-PROCESS'   => IN_PROCESS,
    'FAILED'       => FAILED,
  }.freeze

  # Upstream's GcalEventAttendeeRole.
  CHAIR           = :chair
  REQUIRED        = :required
  OPTIONAL        = :optional
  NON_PARTICIPANT = :non_participant
  ROLE_NONE       = :none

  ROLES = {
    'CHAIR'           => CHAIR,
    'REQ-PARTICIPANT' => REQUIRED,
    'OPT-PARTICIPANT' => OPTIONAL,
    'NON-PARTICIPANT' => NON_PARTICIPANT,
  }.freeze

  # Upstream's GcalEventAttendeeTypeFilterFlags, used by the attendees
  # section to show people and resources separately.
  FILTER_NONE     = 0
  FILTER_PERSON   = 1 << 0
  FILTER_RESOURCE = 1 << 1

  PERSON_TYPES = [INDIVIDUAL, GROUP].freeze
  RESOURCE_TYPES = [RESOURCE, ROOM].freeze

  attr_reader :uri,
    :name,
    :attendee_type,
    :part_status,
    :role,
    :member,
    :delegated_from,
    :delegated_to,
    :sent_by,
    :language

  def initialize(uri:, **attributes)
    @uri = uri.to_s
    @name = attributes.fetch(:name, '').to_s
    @attendee_type = attributes.fetch(:attendee_type, TYPE_NONE)
    @part_status = attributes.fetch(:part_status, PART_NONE)
    @role = attributes.fetch(:role, ROLE_NONE)
    @member = attributes.fetch(:member, nil)
    @delegated_from = attributes.fetch(:delegated_from, nil)
    @delegated_to = attributes.fetch(:delegated_to, nil)
    @sent_by = attributes.fetch(:sent_by, nil)
    @language = attributes.fetch(:language, nil)
    @requires_rsvp = attributes.fetch(:requires_rsvp, false)
  end

  # Upstream's gcal_event_attendee_get_requires_rsvp().
  def requires_rsvp? = @requires_rsvp

  # The address behind the CAL-ADDRESS URI, which is what every row in the
  # attendees section actually shows.
  def email = Utils.email_from_mailto_uri(uri)

  # The name when the attendee has one, the address otherwise — upstream's
  # fallback in the attendee row.
  def display_name
    case name
    when '', nil then email
    else name
    end
  end

  def person? = PERSON_TYPES.include?(attendee_type)

  def resource? = RESOURCE_TYPES.include?(attendee_type)

  # Whether this attendee passes the attendees section's type filter.
  def matches_filter?(flags)
    if flags == FILTER_NONE
      true
    else
      ((flags & FILTER_PERSON).positive? && person?) ||
        ((flags & FILTER_RESOURCE).positive? && resource?)
    end
  end

  # Builds an attendee from an iCalendar ATTENDEE property: the parameters
  # before the value, then the CAL-ADDRESS itself.
  def self.parse(property)
    value, parameters = split_property(property)
    new(
      uri:            value,
      name:           parameters.fetch('CN', ''),
      attendee_type:  TYPES.fetch(parameters.fetch('CUTYPE', '').upcase, TYPE_NONE),
      part_status:    PART_STATUSES.fetch(parameters.fetch('PARTSTAT', '').upcase, PART_NONE),
      role:           ROLES.fetch(parameters.fetch('ROLE', '').upcase, ROLE_NONE),
      member:         parameters['MEMBER'],
      delegated_from: parameters['DELEGATED-FROM'],
      delegated_to:   parameters['DELEGATED-TO'],
      sent_by:        parameters['SENT-BY'],
      language:       parameters['LANGUAGE'],
      requires_rsvp:  parameters.fetch('RSVP', '').upcase == 'TRUE',
    )
  end

  # Splits "ATTENDEE;CN=Ada;RSVP=TRUE:mailto:ada@example.com" into the
  # CAL-ADDRESS and the parameter hash. Quoted parameter values are
  # unquoted, which is what keeps a CN containing a colon intact.
  def self.split_property(property)
    body = property.to_s.strip.sub(/\AATTENDEE/i, '')
    pieces = scan_parameters(body)
    [pieces.fetch(:value, ''), pieces.fetch(:parameters, {})]
  end

  # Walks the property body a character at a time, tracking whether we are
  # inside a quoted string, so that ';' and ':' inside quotes are literal.
  def self.scan_parameters(body)
    parameters = {}
    buffer = ''
    quoted = false
    value = nil

    body.each_char do |char|
      if char == '"'
        quoted = !quoted
        next
      end

      if quoted
        buffer += char
        next
      end

      case char
      when ';'
        store_parameter(parameters, buffer)
        buffer = ''
      when ':'
        store_parameter(parameters, buffer)
        buffer = ''
        value = ''
      else
        if value.nil?
          buffer += char
        else
          value += char
        end
      end
    end

    { value: value.to_s.strip, parameters: parameters }
  end

  def self.store_parameter(parameters, buffer)
    key, parameter_value = buffer.split('=', 2)
    unless key.to_s.strip.empty? || parameter_value.nil?
      parameters[key.strip.upcase] = parameter_value.strip
    end
    parameters
  end

  # The ATTENDEE property this attendee serialises to.
  def to_property
    parameters = {
      'CUTYPE'   => TYPES.key(attendee_type),
      'ROLE'     => ROLES.key(role),
      'PARTSTAT' => PART_STATUSES.key(part_status),
      'CN'       => name,
      'MEMBER'   => member,
      'SENT-BY'  => sent_by,
      'LANGUAGE' => language,
    }
    if requires_rsvp?
      parameters['RSVP'] = 'TRUE'
    end

    rendered = parameters.reject { |_key, parameter| parameter.to_s.empty? }
                         .map { |key, parameter| ";#{key}=#{quote(parameter)}" }
                         .join
    "ATTENDEE#{rendered}:#{uri}"
  end

  private

    # Parameter values containing a separator have to be quoted for the
    # property to round-trip.
    def quote(value)
      if value.to_s.match?(/[;:,]/)
        "\"#{value}\""
      else
        value.to_s
      end
    end
end
