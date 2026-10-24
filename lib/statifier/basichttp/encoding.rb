# frozen_string_literal: true

module Statifier
  module BasicHTTP
    # The Basic HTTP processor's text encodings, as the reference writes and
    # reads them (`Statifier.Send.BasicHTTP` in statifier-ex): a form body
    # and a query string (its `URI.encode_query(pairs, :www_form)` and
    # `URI.query_decoder(text, :www_form)`), the two escaped fields of the
    # `scxml-send-key` header (`URI.encode/2` keeping RFC 3986's unreserved
    # set, and `URI.decode/1`), and a parameter value written as text (its
    # private `encode/1` and `json/1`).
    #
    # Every encoding works on a string's bytes, so a value that is not UTF-8
    # is escaped byte for byte, as the reference escapes one.
    #
    # @api private
    module Encoding
      module_function

      # The bytes neither encoding escapes: RFC 3986's unreserved set.
      ESCAPED = /[^A-Za-z0-9\-._~]/n

      # An escape the decoders read: `%` and two hex digits.
      ESCAPE = /%(\h\h)/n

      # The deepest a list or a map is written as JSON text; one nested
      # deeper is written as predicator's tagged-value text instead, whose
      # encoder refuses past its own limit.
      JSON_DEPTH = 256

      # The magnitude from which a float is always written with an exponent,
      # as the reference's runtime writes it: 2 to the 53rd.
      EXPONENT_FROM = 2**53

      # The JSON escapes of the characters with a short one.
      SHORT_ESCAPES = { '"' => '\\"', "\\" => "\\\\", "\b" => "\\b", "\t" => "\\t", "\n" => "\\n", "\f" => "\\f",
                        "\r" => "\\r" }.freeze

      # Name and value pairs as an `application/x-www-form-urlencoded` body,
      # in the order given: every byte outside the unreserved set escaped as
      # `%` and two upper-case hex digits, a space written `+`.
      #
      # @param pairs [Array<Array(String, String)>]
      # @return [String]
      def form(pairs) = pairs.map { |name, value| "#{www_form(name)}=#{www_form(value)}" }.join("&")

      # One name or value of a form: escaped, a space as `+`.
      def www_form(text) = text.b.gsub(ESCAPED) { _1 == " " ? "+" : format("%%%02X", _1.ord) }.force_encoding("UTF-8")

      # A `scxml-send-key` field: every byte outside the unreserved set
      # escaped, a space as `%20`, so the field carries no `/`.
      #
      # @param text [String]
      # @return [String]
      def field(text) = text.b.gsub(ESCAPED) { format("%%%02X", _1.ord) }.force_encoding("UTF-8")

      # A form body or a query string as its name and value pairs, in order,
      # or nil when a name or a value does not decode to UTF-8. Pairs are
      # split at each `&` and a pair at its first `=`; a pair with no `=` has
      # the empty value, an empty pair is two empty strings, and nothing
      # after a final `&` is a pair.
      #
      # @param text [String]
      # @return [Array<Array(String, String)>, nil]
      def pairs(text)
        out = []
        rest = text.b
        until rest.empty?
          pair, _, rest = rest.partition("&")
          name, _, value = pair.partition("=")
          out << [decoded(name, plus: true), decoded(value, plus: true)]
        end
        out.flatten.all? ? out : nil
      end

      # A field escaped as {field} escapes one, decoded, or nil when it does
      # not decode to UTF-8. A `+` stays a `+`.
      def unfield(text) = decoded(text.b, plus: false)

      # Text with each escape decoded to its byte (an escape that is not `%`
      # and two hex digits stays as it is written) and, when `plus`, each
      # `+` read as a space; nil when the bytes are not UTF-8.
      def decoded(bytes, plus:)
        bytes = bytes.tr("+", " ") if plus
        text = bytes.gsub(ESCAPE) { Regexp.last_match(1).hex.chr }.force_encoding("UTF-8")
        text.valid_encoding? ? text : nil
      end

      # A value written as text: a string as it is, nil as `null`,
      # `Predicator::UNDEFINED` as the empty string, a boolean as its
      # literal, an Integer in decimal, a finite Float as {float} writes it,
      # a list or a map as JSON text ({json}) when every value inside it has
      # a JSON form. Anything else (a date, a datetime, a duration, a list
      # or a map holding a value with no JSON form) is predicator's
      # tagged-value text, or the empty string when that encoder refuses it.
      #
      # @param value [Object] a predicator value
      # @return [String]
      def value(value)
        case value
        when String then value
        when nil then "null"
        when true, false, Integer then value.to_s
        when Float then value.finite? ? float(value) : tagged(value)
        else scalar_or_tagged(value)
        end
      end

      # What {value} writes for a value that is not a String, nil, a
      # boolean or a number.
      def scalar_or_tagged(value)
        return "" if value.equal?(Predicator::UNDEFINED)

        (json(value) if value.is_a?(Array) || value.is_a?(Hash)) || tagged(value)
      end

      # Predicator's tagged-value text of `value`, or the empty string.
      def tagged(value)
        encoded = Predicator::Tagged.encode(value)
        encoded.ok? ? encoded.value : ""
      end

      # A list or a map as JSON text, or nil when a value inside has no JSON
      # form. Inside, `Predicator::UNDEFINED` and nil are `null`; a map's
      # keys must be UTF-8 Strings, and its members stand in the byte order
      # of their keys; a string must be UTF-8; a Float must be finite; a
      # value nested deeper than {JSON_DEPTH} has none. Byte order is the
      # order the reference's runtime lists a small map's string keys in (32
      # keys or fewer); it lists a larger map in an order of its own, so for
      # a map of more than 32 keys this text differs from the reference's.
      #
      # @param value [Array, Hash]
      # @return [String, nil]
      def json(value, depth = 1)
        return nil if depth > JSON_DEPTH

        case value
        when Array then json_list(value, depth)
        when Hash then json_map(value, depth)
        else json_scalar(value)
        end
      end

      def json_list(list, depth)
        parts = list.map { json(_1, depth + 1) || (return nil) }
        "[#{parts.join(",")}]"
      end

      def json_map(map, depth)
        return nil unless map.each_key.all? { _1.is_a?(String) && utf8?(_1) }

        parts = map.keys.sort_by(&:b).map { "#{json_string(_1)}:#{json(map[_1], depth + 1) || (return nil)}" }
        "{#{parts.join(",")}}"
      end

      def json_scalar(value)
        case value
        when nil, Predicator::UNDEFINED then "null"
        when true, false, Integer then value.to_s
        when Float then float(value) if value.finite?
        when String then json_string(value) if utf8?(value)
        end
      end

      # A UTF-8 string as JSON text, as the reference's runtime writes one:
      # `"` and `\` escaped, the control characters with a short escape
      # written so, every other control character below U+0020 as `\u` and
      # four upper-case hex digits, everything else as it is.
      def json_string(text)
        body = utf8(text).gsub(/["\\\x00-\x1f]/) { SHORT_ESCAPES.fetch(_1) { |char| format("\\u%04X", char.ord) } }
        "\"#{body}\""
      end

      # Whether `text`'s bytes are UTF-8.
      def utf8?(text) = utf8(text).valid_encoding?

      # `text`'s bytes read as UTF-8.
      def utf8(text) = text.encoding == ::Encoding::UTF_8 ? text : text.dup.force_encoding("UTF-8")

      # A finite Float as the reference's runtime writes it: the shortest
      # digits that read back as the same number, in the plain form (a point,
      # and `.0` when whole) or the exponent form (one digit, a point, at
      # least one more digit, `e` and the exponent, signed only when
      # negative), whichever is shorter, the plain form on a tie; from 2 to
      # the 53rd up always the exponent form. Zero is `0.0`, and negative
      # zero `-0.0`.
      #
      # @param number [Float] a finite Float
      # @return [String]
      def float(number)
        sign = number.to_s.start_with?("-") ? "-" : ""
        return "#{sign}0.0" if number.zero?

        digits, point = shortest_digits(number.abs)
        exponent = exponent_form(digits, point)
        return sign + exponent if number.abs >= EXPONENT_FROM

        plain = plain_form(digits, point)
        sign + (plain.size <= exponent.size ? plain : exponent)
      end

      # The shortest significant digits of a positive Float, without leading
      # or trailing zeros, and where the point falls: the Float is
      # 0.DIGITS times ten to the power `point`. Ruby's Float#to_s writes the
      # same shortest digits, in a form of its own read apart here.
      def shortest_digits(magnitude)
        mantissa, exponent = magnitude.to_s.split("e")
        whole, fraction = mantissa.split(".")
        digits = whole + fraction
        significant = digits.sub(/\A0+/, "")
        [significant.sub(/0+\z/, ""), whole.size + exponent.to_i - (digits.size - significant.size)]
      end

      def exponent_form(digits, point) = "#{digits[0]}.#{digits.size > 1 ? digits[1..] : "0"}e#{point - 1}"

      def plain_form(digits, point)
        return "0.#{"0" * -point}#{digits}" if point <= 0
        return "#{digits}#{"0" * (point - digits.size)}.0" if digits.size <= point

        "#{digits[0, point]}.#{digits[point..]}"
      end
    end
  end
end
