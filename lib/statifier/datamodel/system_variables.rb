# frozen_string_literal: true

module Statifier
  module Datamodel
    # The specification's system variables (section 5.10) as datamodel
    # values, as the reference writes them. A field with no value is
    # `Predicator::UNDEFINED`, never nil, which is predicator's null.
    #
    # @api private
    module SystemVariables
      # The SCXML Event I/O Processor's type URI, the key of its
      # `_ioprocessors` entry.
      SCXML_EVENT_PROCESSOR = "http://www.w3.org/TR/scxml/#SCXMLEventProcessor"

      module_function

      # The address a session is reached at through the SCXML Event I/O
      # Processor.
      def scxml_location(session_id) = "#_scxml_#{session_id}"

      # The four system variables before any event. `_sessionid` is the id
      # the host minted; `_name` the chart's name, undefined when it has
      # none; `_event` declared with no value, so a read before the first
      # event answers undefined rather than failing; `_ioprocessors` an entry
      # per registered send type (`entries`, by type) and the SCXML Event I/O
      # Processor's, which a registered type of the same spelling never
      # replaces.
      def initial(session_id:, name:, entries: {})
        {
          "_sessionid" => session_id,
          "_name" => name.nil? ? Predicator::UNDEFINED : name,
          "_event" => Predicator::UNDEFINED,
          "_ioprocessors" => entries.merge(SCXML_EVENT_PROCESSOR => { "location" => scxml_location(session_id) })
        }.freeze
      end

      # A session's starting datamodel: the host's roots with the system
      # variables over them, so a host value under a system variable's name
      # never survives.
      def seed(host, session_id:, name:, entries: {}) = host.merge(initial(session_id:, name:, entries:)).freeze

      # The fields of `_event` an event may not carry.
      OPTIONAL_FIELDS = %i[sendid origin origintype invokeid].freeze

      # `_event`'s value for an event: its name, its type (`:internal`,
      # `:external` or `:platform`) as text, each of {OPTIONAL_FIELDS}
      # (keywords in `optional`) undefined when the event has none, and its
      # data as it is.
      #
      # @raise [ArgumentError] for a keyword that names no field of `_event`
      def event(name:, type:, data:, **optional)
        unknown = optional.keys - OPTIONAL_FIELDS
        raise ArgumentError, "unknown _event fields: #{unknown.inspect}" unless unknown.empty?

        fields = OPTIONAL_FIELDS.to_h { [_1.to_s, absent(optional[_1])] }
        { "name" => name, "type" => type.to_s, **fields, "data" => data }.freeze
      end

      # The datamodel with `_event` set to `event_value` ({event}).
      def put_event(data, event_value) = data.merge("_event" => event_value).freeze

      # nil, a field the event does not carry, as undefined.
      def absent(value) = value.nil? ? Predicator::UNDEFINED : value
    end
  end
end
