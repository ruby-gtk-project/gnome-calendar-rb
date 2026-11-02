# frozen_string_literal: true

require_relative 'utils'
require_relative 'event_attendee'

# EventOrganizer is the ORGANIZER of an event — the one address an invitation
# came from, shown above the attendee list and never editable.
#
# Ported from upstream's src/core/gcal-event-organizer.c.
#
class EventOrganizer
  attr_reader :uri, :name, :sent_by, :language

  def initialize(uri:, name: '', sent_by: nil, language: nil)
    @uri = uri.to_s
    @name = name.to_s
    @sent_by = sent_by
    @language = language
  end

  # The address behind the CAL-ADDRESS URI.
  def email = Utils.email_from_mailto_uri(uri)

  # The name when there is one, the address otherwise.
  def display_name
    case name
    when '', nil then email
    else name
    end
  end

  # Builds an organizer from an iCalendar ORGANIZER property. The property
  # has the same shape as ATTENDEE, so the attendee's scanner does the work.
  def self.parse(property)
    value, parameters = EventAttendee.split_property(property.to_s.strip.sub(/\AORGANIZER/i, 'ATTENDEE'))
    new(
      uri:      value,
      name:     parameters.fetch('CN', ''),
      sent_by:  parameters['SENT-BY'],
      language: parameters['LANGUAGE'],
    )
  end

  # The ORGANIZER property this organizer serialises to.
  def to_property
    parameters = {
      'CN'       => name,
      'SENT-BY'  => sent_by,
      'LANGUAGE' => language,
    }
    rendered = parameters.reject { |_key, value| value.to_s.empty? }
                         .map { |key, value| ";#{key}=#{value}" }
                         .join
    "ORGANIZER#{rendered}:#{uri}"
  end
end
