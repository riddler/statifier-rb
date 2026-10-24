# frozen_string_literal: true

module Statifier
  module BasicHTTP
    # A send the processor could not deliver, as it hands it to the host's
    # `report:` callable: the host passes `effect` and `reason` to
    # {Statifier.report_send_failed} with the state it holds for
    # `session_id`.
    #
    # @!attribute [r] session_id
    #   @return [String] the sending session's id
    # @!attribute [r] effect
    #   @return [Statifier::Effect::Send, Statifier::Effect::SendDelayed] the
    #     send the processor was handed
    # @!attribute [r] reason
    #   @return [Symbol] why: `:http_status` (a response outside 2xx),
    #     `:transport_error` (the transport raised), `:invalid_target` (a
    #     target that is not a String) or `:no_timer` (a delayed send, which
    #     this processor holds no timer for)
    # @!attribute [r] detail
    #   @return [Object, nil] the {Response} for `:http_status`; for
    #     `:transport_error`, the error the transport raised, or a TypeError
    #     when it answered something that is not a {Response}; the target
    #     for `:invalid_target`; nil for `:no_timer`
    Failure = ::Data.define(:session_id, :effect, :reason, :detail)

    # The Basic HTTP Event I/O Processor (SCXML appendix C.2), outbound, as
    # the reference's `Statifier.Send.BasicHTTP` is: a processor a host
    # registers like any other, under {EVENT_PROCESSOR} and its short form
    # {SHORT_TYPE} ({#send_types} names it under both).
    #
    # Each send it is handed becomes one POST, made once through the
    # transport while `deliver` runs. The request is built from the send's
    # data, as the reference builds it:
    #
    # - a Hash is a form body (`application/x-www-form-urlencoded`): the
    #   event name as the `_scxmleventname` parameter, then each name and
    #   value, in the byte order of the names (the reference lists a map of
    #   more than 32 names in an order of its own, so such a body differs);
    # - no data (`Predicator::UNDEFINED`) is a form body of the event name
    #   alone;
    # - any other value is the body, as `text/plain`, with the event name as
    #   `_scxmleventname` in the target's query string.
    #
    # A value is written as {Encoding.value} writes it, and a send with no
    # event name carries no `_scxmleventname`. Every request carries the
    # send's deduplication key in the `scxml-send-key` header ({.send_key}),
    # the same value each time the same send is handed, so a receiver that
    # deduplicates on it takes each send once.
    #
    # A send with no target fails within the call that handed it, as
    # appendix C.2.2 requires: `deliver` answers a
    # {Statifier::Driver::DeliveryFailure} and makes no request. Any other
    # miss is handed to the host's `report:` callable as a {Failure} before
    # `deliver` returns, as the reference's processor reports a miss to the
    # sending session, which takes it after the step it is in: a response
    # outside 2xx, a transport that raised, a target that is not a String
    # and a delayed send, which this processor holds no timer for. The host
    # passes each to {Statifier.report_send_failed} once the call that
    # handed the send has returned, with the state that call answered.
    #
    # The processor keeps nothing between sends and is frozen; one
    # processor serves every session it is registered for.
    #
    # @example
    #   misses = []
    #   http = Statifier::BasicHTTP::Processor.new(base_url: "http://localhost:8080/scxml", report: misses.method(:<<))
    #   moved = Statifier.start(machine, session_id: "s1", processors: http.send_types).value
    #   misses.each do |miss|
    #     moved = Statifier.report_send_failed(machine, moved.state, miss.effect, reason: miss.reason,
    #                                          processors: http.send_types).value
    #   end
    class Processor
      # The form parameter that carries the event name.
      EVENT_NAME_PARAM = "_scxmleventname"

      # The content type of a form body.
      FORM = "application/x-www-form-urlencoded"

      # The header that carries the send's deduplication key.
      SEND_KEY_HEADER = "scxml-send-key"

      # @return [String] the address the host's own front answers at
      attr_reader :base_url

      # @param base_url [String] the address the host's own front answers
      #   at; a session's `_ioprocessors` location is this address, `/` and
      #   the session's id. Copied, never frozen in place
      # @param report [#call] takes each {Failure}, before `deliver`
      #   returns; its answer is not read, and an error it raises is not
      #   caught
      # @param transport [#call, nil] makes each request ({BasicHTTP} says
      #   what a transport is); a {NetHTTPTransport} with its defaults when
      #   nil
      # @raise [TypeError] for a base URL that is not a String
      # @raise [ArgumentError] for an empty base URL, or a `report` or a
      #   `transport` that does not answer `call`
      def initialize(base_url:, report:, transport: nil)
        raise ArgumentError, "expected report to answer call" unless report.respond_to?(:call)
        raise ArgumentError, "expected transport to answer call" unless transport.nil? || transport.respond_to?(:call)

        @base_url = address(base_url)
        @report = report
        @transport = transport || NetHTTPTransport.new
        freeze
      end

      # The send types to register this processor under, as a host passes
      # them in `processors:`: {EVENT_PROCESSOR} and {SHORT_TYPE}, so a chart
      # may name either and `_ioprocessors` carries an entry under each.
      #
      # @return [Hash{String => Processor}] a frozen Hash
      def send_types = { EVENT_PROCESSOR => self, SHORT_TYPE => self }.freeze

      # The `_ioprocessors` entry for a session (appendix C.2.3): its
      # `"location"`, the base URL, `/` and the session's id, the same under
      # either type.
      #
      # @param _type [String] the type it is registered under
      # @param context [Statifier::Driver::Context] the session
      # @return [Hash{String => String}] a frozen Hash
      def ioprocessors_entry(_type, context) = { "location" => "#{base_url}/#{context.session_id}".freeze }.freeze

      # Takes one send (see the class's description): makes its request, or
      # answers a {Statifier::Driver::DeliveryFailure} for a send with no
      # target.
      #
      # @param send [Statifier::Effect::Send, Statifier::Effect::SendDelayed]
      # @param _event [Statifier::Event] the event a delivery would carry,
      #   not read
      # @param context [Statifier::Driver::Context] the sending session
      # @return [Statifier::Driver::DeliveryFailure, nil]
      def deliver(send, _event, context)
        return Driver::DeliveryFailure.new(reason: :no_target) if send.target.nil?

        session_id = context.session_id
        return miss(session_id, send, :no_timer, nil) if send.is_a?(Effect::SendDelayed)
        return miss(session_id, send, :invalid_target, send.target) unless send.target.is_a?(String)

        post(session_id, send)
      end

      # The request one send becomes (see the class's description).
      #
      # @param session_id [String] the sending session's id
      # @param send [Statifier::Effect::Send, Statifier::Effect::SendDelayed]
      #   a send whose target is a String
      # @return [Request]
      def self.request(session_id, send)
        url, content_type, body = message(send)
        Request.new(http_method: "POST", url:, headers: [["content-type", content_type],
                                                         [SEND_KEY_HEADER, send_key(session_id, send)]], body:)
      end

      # The URL, the content type and the body of the send's request.
      def self.message(send)
        named = send.event ? [[EVENT_NAME_PARAM, Encoding.value(send.event)]] : []
        data = send.data
        if data.is_a?(Hash)
          [send.target, FORM, Encoding.form(named + fields(data))]
        elsif data.equal?(Predicator::UNDEFINED)
          [send.target, FORM, Encoding.form(named)]
        else
          [with_query(send.target, named), "text/plain", Encoding.value(data)]
        end
      end

      # A Hash's names and values as form fields, in the byte order of the
      # names.
      def self.fields(data)
        data.map { |name, value| [Encoding.value(name), Encoding.value(value)] }.sort_by { _1.first.b }
      end

      # A send's deduplication key, as the `scxml-send-key` header carries
      # it and the reference spells it: eight fields joined by `/`, the
      # session's id and the send id escaped ({Encoding.field}), the
      # macrostep, microstep, round and content index in decimal, the owner
      # (`onentry.S.B`, `onexit.S.B`, `finalize.S.B` with the state's index
      # and the block's, or `transition.T`) and the ordinal; a field the send
      # does not carry is empty.
      #
      # @param session_id [String] the sending session's id
      # @param send [Statifier::Effect::Send, Statifier::Effect::SendDelayed]
      # @return [String]
      def self.send_key(session_id, send)
        [Encoding.field(session_id), Encoding.field(send.send_id), send.macrostep, send.microstep, send.round,
         send.c_index, owner(send.owner), send.ordinal].join("/")
      end

      # A content owner as the key spells it.
      def self.owner(owner)
        case owner&.fetch(:kind)
        when :onentry, :onexit then "#{owner[:kind]}.#{owner[:state_index]}.#{owner[:ordinal]}"
        when :finalize then "finalize.#{owner[:state_index]}.#{owner[:invoke_index]}"
        when :transition then "transition.#{owner[:t_index]}"
        end
      end

      # `url` with the pairs appended as a query string, after `&` when it
      # already carries one.
      def self.with_query(url, pairs)
        return url if pairs.empty?

        "#{url}#{url.include?("?") ? "&" : "?"}#{Encoding.form(pairs)}"
      end

      private_class_method :message, :fields, :owner, :with_query

      private

      # `base_url`, checked, as a frozen copy.
      def address(base_url)
        raise TypeError, "expected base_url to be a String, got #{base_url.class}" unless base_url.is_a?(String)
        raise ArgumentError, "expected base_url to be an address, got an empty String" if base_url.empty?

        base_url.frozen? ? base_url : base_url.dup.freeze
      end

      # The send's request made once, and a miss handed to the host.
      def post(session_id, send)
        answered = exchange(self.class.request(session_id, send))
        return miss(session_id, send, :transport_error, answered) if answered.is_a?(Exception)
        return miss(session_id, send, :http_status, answered) unless (200..299).cover?(answered.status)

        nil
      end

      # What the transport answered for `request`: its {Response}, or the
      # error it raised, a transport that answers anything but a {Response}
      # answered as a TypeError.
      def exchange(request)
        answered = @transport.call(request)
        answered.is_a?(Response) ? answered : TypeError.new("expected a #{Response}, got #{answered.class}")
      rescue StandardError => e
        e
      end

      # A miss handed to the host's `report:`; `deliver` answers nil.
      def miss(session_id, send, reason, detail)
        @report.call(Failure.new(session_id:, effect: send, reason:, detail:))
        nil
      end
    end
  end
end
