# frozen_string_literal: true

require_relative "../../lib/statifier/basichttp"

module Conformance
  # The loopback front: the in-memory half of a Basic HTTP round trip, which
  # the conformance runner delivers the package's Basic HTTP processor's
  # requests through.
  #
  # The reference's harness starts a loopback front for every case whose
  # host object names an Event I/O Processor (`with_event_io_processors/2`
  # in lib/mix/statifier/corpus/host_case.ex at the tag the copy names): an
  # HTTP server on a free local port (`Mix.Statifier.BasicHTTPFront` in
  # lib/mix/statifier/basic_http_front.ex), whose base URL the processor is
  # registered with. A request to that base URL, `/` and a session's id is
  # decoded by the processor's own decoder and the event it carries is
  # enqueued on that session as an external event. Its status rule is the
  # decoder's: 204 once the event is enqueued, 405 with `Allow: POST` for a
  # method other than POST, 400 for a request that forms no event, and 404
  # for a path that names no live session. It does not deduplicate on the
  # `scxml-send-key` header.
  #
  # This front is that one in memory: a transport ({Front}, a callable the
  # processor takes as its `transport:`) that reads the request's URL
  # against the front's base URL, decodes the request with
  # {Statifier::BasicHTTP.decode} and holds the event for the runner, which
  # steps it into the session once the driver call that made the request
  # has returned ({Wire#exchange}). No socket is opened and nothing leaves
  # the process: the base URL's host is under `.invalid`, a name that never
  # resolves, and the processor is never handed a transport that could make
  # a request. So a case it delivers proves the processor's and the core's
  # event path, not a network round trip. The front answers for the case's
  # own session, the one the runner starts; no vendored case addresses a
  # session an invoked child runs.
  #
  # A request over the loopback takes no virtual time, so a chart that sends
  # to itself through the processor on every delivery would never let an
  # exchange end: an exchange is bounded at MAX_EXCHANGE_ROUNDS rounds, and a
  # case past the bound fails naming it. The reference's harness ends such a
  # chart at its real deadline instead.
  module Loopback
    # The base URL the front answers at: the reference front's path prefix,
    # `/basichttp`, on a host name that resolves nowhere.
    BASE_URL = "http://loopback.invalid/basichttp"

    # The most rounds one exchange takes: a round is every arrival taken
    # since the last, each handed to the driver. A run of the vendored cases
    # that name a processor takes at most two rounds in any one exchange.
    MAX_EXCHANGE_ROUNDS = 100

    # The reason a case fails with when one exchange passes the bound.
    NOT_SETTLED = "the exchange with the loopback front did not settle within #{MAX_EXCHANGE_ROUNDS} rounds".freeze

    # Raised by {Wire#exchange} past the bound; the drive answers its
    # message as the case's reason.
    class NotSettled < StandardError; end

    # One thing the wire holds for the runner: an event the front took
    # (`kind` :event, `value` the {Statifier::Event}) or a miss the processor
    # reported (`kind` :missed, `value` the {Statifier::BasicHTTP::Failure}).
    Arrival = ::Data.define(:kind, :value)

    # The front, a transport: it answers each request by the reference
    # front's status rule, and hands each event it takes to `enqueue`.
    class Front
      # @return [String] the base URL it answers at
      attr_reader :base_url

      # A front at `base_url` answering for each session id `live` accepts.
      def initialize(live, base_url = BASE_URL, &enqueue)
        @live = live
        @base_url = base_url
        @enqueue = enqueue
      end

      # The transport's call: the {Statifier::BasicHTTP::Response} for
      # `request`, which carries no body.
      def call(request)
        status = status(request)
        headers = status == 405 ? [%w[allow POST]] : []
        Statifier::BasicHTTP::Response.new(status:, headers:)
      end

      # The status the front answers `request` with, the event it carries
      # enqueued when it answers 204.
      def status(request)
        session_id, query = addressed(request.url)
        return 404 unless session_id && @live.call(session_id)

        decoded = Statifier::BasicHTTP.decode(method: request.http_method,
                                              content_type: header(request, "content-type"), body: request.body,
                                              query:, send_key: header(request, "scxml-send-key"))
        return decoded.error.reason == :method_not_allowed ? 405 : 400 unless decoded.ok?

        @enqueue.call(decoded.value)
        204
      end

      private

      # The session id and the query string `url` addresses under the base
      # URL, or nil for a URL outside it.
      def addressed(url)
        prefix = "#{base_url}/"
        return unless url.start_with?(prefix)

        path, query = url.delete_prefix(prefix).split("?", 2)
        [path, query]
      end

      # The first value of the header `name`, in any case, or nil.
      def header(request, name)
        request.headers.find { |key, _value| key.casecmp?(name) }&.last
      end
    end

    # The loopback for one case: the front, answering for the case's own
    # session, and what it and the processor's `report:` bring back.
    class Wire
      # @return [Front]
      attr_reader :front

      # A wire whose front answers for `session_id` alone.
      def initialize(session_id, base_url: BASE_URL)
        @arrivals = []
        @front = Front.new(->(id) { id == session_id }, base_url) { @arrivals << Arrival.new(kind: :event, value: _1) }
      end

      # What an Event I/O Processor is made with: the front's base URL, the
      # front as its transport and the wire as its `report:`.
      def options = { base_url: front.base_url, transport: front, report: method(:missed) }

      # The processors to hand the driver on every call for a case naming
      # `uris`: the send types of the entry of `provided` for each, made
      # with this wire.
      def register(uris, provided)
        uris.each_with_object({}) { |uri, types| types.merge!(provided.fetch(uri).call(self)) }
      end

      # The processor's `report:`: the miss held for the runner.
      def missed(failure)
        @arrivals << Arrival.new(kind: :missed, value: failure)
      end

      # What arrived since the last call, in the order it arrived.
      def take
        taken = @arrivals
        @arrivals = []
        taken
      end

      # `state` after every arrival is handed to the block, which answers the
      # state that follows it; the arrivals the block's own calls bring back
      # are taken in the next round, until a round brings nothing back. A
      # round past MAX_EXCHANGE_ROUNDS that brings something back raises
      # {NotSettled}.
      def exchange(state)
        (1..).each do |round|
          arrivals = take
          return state if arrivals.empty?
          raise NotSettled, NOT_SETTLED if round > MAX_EXCHANGE_ROUNDS

          arrivals.each { state = yield(state, _1) }
        end
      end
    end

    # The processors the host object names that `provided` holds no entry
    # for, as the reason, or nil.
    def self.not_provided(host, provided)
      missing = named(host).reject { provided.key?(_1) }
      return if missing.empty?

      "the case's host object names the Event I/O Processor #{missing.join(", ")}, " \
        "which this package does not provide"
    end

    # The URIs a host object's `event_io_processors` names, in order; a value
    # that is not a list is named whole, as it came, so it is refused.
    def self.named(host)
      value = host.fetch("event_io_processors", [])
      value.is_a?(Array) ? value : [value.inspect]
    end

    # The Event I/O Processors the runner provides, by the URI a case's
    # `host.event_io_processors` names them under, as the reference's
    # harness keys its closed set (`@event_io_processors` in host_case.ex):
    # each entry takes a case's {Wire} and answers a Hash of send type to
    # processor, every type the processor is registered under. Its one
    # member is the package's Basic HTTP processor, registered with the
    # wire's front under its URI and its short form `basichttp`.
    PROCESSORS = {
      Statifier::BasicHTTP::EVENT_PROCESSOR => ->(wire) { Statifier::BasicHTTP::Processor.new(**wire.options).send_types }
    }.freeze
  end
end
