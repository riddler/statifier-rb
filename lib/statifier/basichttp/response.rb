# frozen_string_literal: true

module Statifier
  module BasicHTTP
    # The response a transport answers, whatever its status: a status
    # outside 2xx is a response, not a {TransportError}. A frozen value,
    # deeply: a string it is built from that is not frozen is copied, never
    # frozen in place, and one already frozen is kept.
    #
    # @!attribute [r] status
    #   @return [Integer] the HTTP status code, from 100 to 599
    # @!attribute [r] headers
    #   @return [Array<Array(String, String)>] name and value pairs, in the
    #     order the transport read them; a name may appear more than once.
    #     {NetHTTPTransport} answers every name in lower case
    # @!attribute [r] body
    #   @return [String] the body as the transport read it; empty for none
    Response = ::Data.define(:status, :headers, :body) do
      # @param status [Integer] the HTTP status code
      # @param headers [Array<Array(String, String)>] name and value pairs;
      #   none when absent
      # @param body [String] the body; empty when absent
      # @raise [TypeError] for a member of the wrong kind
      # @raise [ArgumentError] for a status outside 100 to 599, or a header
      #   as {Request} refuses one
      def initialize(status:, headers: [], body: "")
        raise TypeError, "expected status to be an Integer, got #{status.class}" unless status.is_a?(Integer)
        raise ArgumentError, "expected status to be from 100 to 599, got #{status}" unless (100..599).cover?(status)

        super(status:, headers: Values.headers(headers), body: Values.string(body, "body"))
      end
    end
  end
end
