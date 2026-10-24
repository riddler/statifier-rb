# frozen_string_literal: true

require_relative "../statifier"

module Statifier
  # The Basic HTTP Event I/O Processor (SCXML appendix C.2), loaded only by
  # `require "statifier/basichttp"`: `require "statifier"` alone loads none
  # of it, and so loads no HTTP library.
  #
  # It holds three things. The {Processor}, a send processor a host
  # registers under {EVENT_PROCESSOR} and {SHORT_TYPE}, turns each send it
  # is handed into one POST. {BasicHTTP.decode} turns an HTTP request a
  # host's own server took into the event it carries. And the HTTP
  # transport is the seam between the processor and whatever makes a
  # request. A transport is anything that responds to `call` (a lambda, a
  # method object, an object): it takes one {Request} (the method, the URL,
  # the headers and the body) and makes it, and it answers the {Response}
  # that came back (the status, the headers and the body), whatever its
  # status, or raises a {TransportError} when no response came back.
  # {NetHTTPTransport} is the default transport, on the standard library's
  # Net::HTTP, and a host may pass any other callable of the same contract
  # instead.
  module BasicHTTP
    # The processor's type, appendix C.2's URI.
    EVENT_PROCESSOR = "http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor"

    # The processor's short type, which a chart may name in its place.
    SHORT_TYPE = "basichttp"

    # A transport answered no response: the URL could not be requested, the
    # connection failed or was refused, a time bound passed, or the exchange
    # broke off. This is the one error a transport raises for a request it
    # could not make; the error that caused it, when there was one, is its
    # `cause`.
    class TransportError < StandardError; end
  end
end

require_relative "basichttp/request"
require_relative "basichttp/response"
require_relative "basichttp/net_http_transport"
require_relative "basichttp/encoding"
require_relative "basichttp/processor"
require_relative "basichttp/decode"
