# frozen_string_literal: true

module Statifier
  # The receive side of the Basic HTTP processor: {BasicHTTP.decode} and
  # its {BasicHTTP::Refusal}.
  module BasicHTTP
    # Why {BasicHTTP.decode} formed no event from a request.
    #
    # @!attribute [r] reason
    #   @return [Symbol] `:method_not_allowed` (the method is not POST; a
    #     front answers 405 with `Allow: POST`), `:not_utf8` (the query
    #     string or the body does not decode to UTF-8) or
    #     `:malformed_send_key` (the `scxml-send-key` value is not eight
    #     fields joined by `/` whose second decodes to UTF-8); a front
    #     answers either of the last two 400
    # @!attribute [r] detail
    #   @return [String, Symbol] the method, `:query` or `:body`, or the
    #     header's value
    Refusal = ::Data.define(:reason, :detail)

    # The event one HTTP request carries (appendix C.2.1), as the
    # reference's `Statifier.Send.BasicHTTP.decode/1` forms it. It is pure
    # and knows no session: a host's own server resolves the request's
    # location to a session, decodes the request here and passes the event's
    # `name` and `data` to {Statifier.step} with the state it holds for that
    # session.
    #
    # - The method must be POST, in any case.
    # - The event's name is the first `_scxmleventname` parameter found, the
    #   query string's before a form body's, else `HTTP.` and the method in
    #   upper case (`HTTP.POST`).
    # - A form body (a content type that begins
    #   `application/x-www-form-urlencoded`, in any case) and the query
    #   string give the other parameters, which are the event's data: a
    #   Hash whose values are each read as a `<content>` body's text is read
    #   (a predicator literal, else the text with its whitespace collapsed),
    #   so `2` is the number 2; the last of a repeated name wins, and no
    #   parameters is no data (`Predicator::UNDEFINED`).
    # - A body of any other content type, a JSON body included, is the data,
    #   read the same way, and the query string then gives the name only. No
    #   charset is read.
    # - The event is external, its `origintype` {EVENT_PROCESSOR} and its
    #   `origin` and `sendid` nil.
    # - The `scxml-send-key` value is checked and sets nothing on the event:
    #   deduplicating on it is the server's. A server that has already taken
    #   a request with the same value answers 204 again and takes nothing.
    #
    # A server answers 204 once it has taken the event, 405 or 400 for a
    # refusal, and its own 404 for a location that names no session it holds.
    #
    # @example
    #   decoded = Statifier::BasicHTTP.decode(method: "POST", content_type: "application/x-www-form-urlencoded",
    #                                         body: "_scxmleventname=e.go&n=2", query: nil)
    #   decoded.value.name # => "e.go"
    #   decoded.value.data # => {"n" => 2}
    #
    # @param method [String] the request's method
    # @param content_type [String, nil] its content type, nil when it carries
    #   none
    # @param body [String] its body, empty for none
    # @param query [String, nil] its query string without the `?`, nil when
    #   the URL has none
    # @param send_key [String, nil] its `scxml-send-key` header's value, nil
    #   when it carries none
    # @return [Statifier::Result] the {Statifier::Event}, deeply frozen, or a
    #   {Refusal}
    # @raise [TypeError] for an argument of the wrong kind
    def self.decode(method:, content_type:, body:, query:, send_key: nil)
      Decode.request(method, content_type, body, query, send_key)
    end

    # The body of {BasicHTTP.decode}.
    #
    # @api private
    module Decode
      module_function

      # {BasicHTTP.decode}'s body, its checks in the reference's order: the
      # method, the query string, the body, the send key.
      def request(method, content_type, body, query, send_key)
        checked(method:, body:, content_type:, query:, send_key:)
        return refused(:method_not_allowed, method) unless method.upcase == "POST"

        query_pairs = query.nil? ? [] : Encoding.pairs(query)
        return refused(:not_utf8, :query) if query_pairs.nil?

        decoded(method, query_pairs, body(content_type, body), send_key)
      end

      # The event, after the body and the send key are checked.
      def decoded(method, query_pairs, (body_pairs, text), send_key)
        return refused(:not_utf8, :body) if body_pairs.nil?
        return refused(:malformed_send_key, send_key) unless send_key.nil? || send_key?(send_key)

        Result.new(value: event(method, query_pairs + body_pairs, text), error: nil)
      end

      # A form body's pairs and no text, or no pairs and the body as text;
      # nil pairs when it does not decode to UTF-8.
      def body(content_type, body)
        return [Encoding.pairs(body), nil] if content_type&.downcase&.start_with?(Outbound::FORM)

        text = Encoding.utf8(body.b)
        text.valid_encoding? ? [[], text] : [nil, nil]
      end

      # Whether `value` is eight fields joined by `/` whose second decodes to
      # UTF-8.
      def send_key?(value)
        fields = value.split("/", -1)
        fields.size == 8 && !Encoding.unfield(fields[1]).nil?
      end

      # The event the pairs and the text carry.
      def event(method, pairs, text)
        named, params = pairs.partition { _1.first == Outbound::EVENT_NAME_PARAM }
        name = named.empty? ? "HTTP.#{method.upcase}" : named.first.last
        data = text ? Interpreter::Send.text_data(text) : params_data(params)
        Frozen.copy(Event.external(name, data:, origintype: EVENT_PROCESSOR))
      end

      # Each parameter's value read as text, the last of a name winning.
      def params_data(params)
        Interpreter::Send.params_data(params.map { |name, value| [name, Interpreter::Send.text_data(value)] })
      end

      def refused(reason, detail) = Result.new(value: nil, error: Refusal.new(reason:, detail: frozen(detail)))

      def frozen(detail) = detail.is_a?(String) ? detail.dup.freeze : detail

      # The arguments, after checking their kinds.
      def checked(**arguments)
        arguments.each do |name, value|
          next if value.is_a?(String) || (value.nil? && !%i[method body].include?(name))

          raise TypeError, "expected #{name} to be a String#{" or nil" unless %i[method body].include?(name)}, " \
                           "got #{value.class}"
        end
      end
    end
  end
end
