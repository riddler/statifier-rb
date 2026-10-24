# frozen_string_literal: true

module Statifier
  module BasicHTTP
    # One request a transport makes, a frozen value, deeply: a string it
    # is built from that is not frozen is copied, never frozen in place, and
    # one already frozen is kept. A transport sends it
    # as it is handed and changes nothing in it.
    #
    # @example
    #   request = Statifier::BasicHTTP::Request.new(
    #     http_method: "POST",
    #     url: "http://localhost:8080/s1",
    #     headers: [["content-type", "text/plain"]],
    #     body: "e.go"
    #   )
    #
    # @!attribute [r] http_method
    #   @return [String] the HTTP method, an HTTP token such as `"POST"`
    # @!attribute [r] url
    #   @return [String] the absolute URL requested
    # @!attribute [r] headers
    #   @return [Array<Array(String, String)>] name and value pairs, in
    #     order; a name may appear more than once. Each name is an HTTP
    #     token, and no value holds a carriage return, a line feed or a NUL
    # @!attribute [r] body
    #   @return [String] the body, already encoded; empty for none
    Request = ::Data.define(:http_method, :url, :headers, :body) do
      # @param http_method [String] the HTTP method
      # @param url [String] the absolute URL
      # @param headers [Array<Array(String, String)>] name and value pairs;
      #   none when absent
      # @param body [String] the body; empty when absent
      # @raise [TypeError] for a member of the wrong kind
      # @raise [ArgumentError] for a method or a header name that is not an
      #   HTTP token, or a header value holding a carriage return, a line
      #   feed or a NUL
      def initialize(http_method:, url:, headers: [], body: "")
        super(
          http_method: Values.token(http_method, "http_method"),
          url: Values.string(url, "url"),
          headers: Values.headers(headers),
          body: Values.string(body, "body")
        )
      end
    end

    # The checks and copies {Request} and {Response} make of what they are
    # built from.
    #
    # @api private
    module Values
      module_function

      # An HTTP token (RFC 9110, section 5.6.2).
      TOKEN = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/

      # `value`, a String, as a frozen copy.
      def string(value, field)
        raise TypeError, "expected #{field} to be a String, got #{value.class}" unless value.is_a?(String)

        value.frozen? ? value : value.dup.freeze
      end

      # `value`, an HTTP token, as a frozen copy.
      def token(value, field)
        copy = string(value, field)
        raise ArgumentError, "expected #{field} to be an HTTP token, got #{copy.inspect}" unless TOKEN.match?(copy)

        copy
      end

      # `value`, a list of name and value pairs, as a frozen copy.
      def headers(value)
        raise TypeError, "expected headers to be an Array of pairs, got #{value.class}" unless value.is_a?(Array)

        value.map { header(_1) }.freeze
      end

      # One name and value pair, as a frozen copy.
      def header(pair)
        unless pair.is_a?(Array) && pair.size == 2
          raise TypeError, "expected each header to be a [name, value] pair, got #{pair.inspect}"
        end

        name = token(pair[0], "a header name")
        value = string(pair[1], "a header value")
        raise ArgumentError, "the value of header #{name} holds CR, LF or NUL" if value.match?(/[\r\n\0]/)

        [name, value].freeze
      end
    end
  end
end
