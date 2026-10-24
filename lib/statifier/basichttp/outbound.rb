# frozen_string_literal: true

module Statifier
  module BasicHTTP
    # The request each send the {Processor} is handed becomes, and the
    # send's deduplication key, built as the reference's processor builds
    # them (the {Processor} says how).
    #
    # @api private
    module Outbound
      # The form parameter that carries the event name.
      EVENT_NAME_PARAM = "_scxmleventname"

      # The content type of a form body.
      FORM = "application/x-www-form-urlencoded"

      # The header that carries the send's deduplication key.
      SEND_KEY_HEADER = "scxml-send-key"

      module_function

      # The request one send becomes ({Processor} says how).
      #
      # @param session_id [String] the sending session's id
      # @param send [Statifier::Effect::Send, Statifier::Effect::SendDelayed]
      #   a send whose target is a String
      # @return [Request]
      def request(session_id, send)
        url, content_type, body = message(send)
        Request.new(http_method: "POST", url:, headers: [["content-type", content_type],
                                                         [SEND_KEY_HEADER, send_key(session_id, send)]], body:)
      end

      # The URL, the content type and the body of the send's request.
      def message(send)
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
      def fields(data)
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
      def send_key(session_id, send)
        [Encoding.field(session_id), Encoding.field(send.send_id), send.macrostep, send.microstep, send.round,
         send.c_index, owner(send.owner), send.ordinal].join("/")
      end

      # A content owner as the key spells it.
      def owner(owner)
        case owner&.fetch(:kind)
        when :onentry, :onexit then "#{owner[:kind]}.#{owner[:state_index]}.#{owner[:ordinal]}"
        when :finalize then "finalize.#{owner[:state_index]}.#{owner[:invoke_index]}"
        when :transition then "transition.#{owner[:t_index]}"
        end
      end

      # `url` with the pairs appended as a query string, after `&` when it
      # already carries one.
      def with_query(url, pairs)
        return url if pairs.empty?

        "#{url}#{url.include?("?") ? "&" : "?"}#{Encoding.form(pairs)}"
      end
    end
  end
end
