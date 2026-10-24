# frozen_string_literal: true

require "net/http"
require "uri"

module Statifier
  module BasicHTTP
    # The default transport, on the standard library's Net::HTTP (the
    # `net-http` default gem), so it adds no runtime dependency.
    #
    # Each {#call} makes one request once, on a connection of its own that
    # it opens and closes, and answers the {Response}, whatever its status;
    # retrying is not a transport's job. It raises a {TransportError} when no
    # response came back: a URL that is not an absolute `http` or `https` URL
    # with a host (no connection is then opened); any error raised while it
    # connects, sends or reads, a host's `connect` included, which is then
    # the error's `cause`; or a status line outside 100 to 599.
    #
    # Net::HTTP adds the headers it always adds (`host`, and the
    # `accept-encoding`, `accept` and `user-agent` defaults) unless the
    # request names them, and a response body it decodes from `gzip` or
    # `deflate` is answered decoded. Two headers of one name in a request are
    # sent as one header, their values joined by a comma.
    #
    # @example
    #   transport = Statifier::BasicHTTP::NetHTTPTransport.new(timeout: 2)
    #   request = Statifier::BasicHTTP::Request.new(http_method: "POST", url: "http://localhost:8080/s1", body: "e.go")
    #   begin
    #     transport.call(request).status # => 200
    #   rescue Statifier::BasicHTTP::TransportError => e
    #     e.message # why no response came back
    #   end
    class NetHTTPTransport
      # How long, in seconds, each of opening the connection, writing the
      # request and reading the response may take when the host names no
      # bound: the reference's five seconds.
      DEFAULT_TIMEOUT = 5

      # The connection the default transport opens for `uri`: a Net::HTTP
      # object, not yet started, for its host and port, using TLS for an
      # `https` URL (with Net::HTTP's default, the peer verified against the
      # default certificate store), each of its open, TLS handshake, write
      # and read bounds `timeout` seconds. A host's own `connect:` callable
      # may call this and change the answer before it returns it (a proxy, a
      # certificate file).
      #
      # @param uri [URI::HTTP] the URL requested
      # @param timeout [Numeric] the bound on each step, in seconds
      # @return [Net::HTTP] the connection, not started
      def self.connection(uri, timeout: DEFAULT_TIMEOUT)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = timeout
          http.ssl_timeout = timeout
          http.write_timeout = timeout
          http.read_timeout = timeout
        end
      end

      # @param timeout [Numeric] the bound, in seconds, on each of opening
      #   the connection, writing the request and reading the response;
      #   {DEFAULT_TIMEOUT} when absent
      # @param connect [#call, nil] answers the connection for a URL, called
      #   with the request's `URI::HTTP`; the connection answers `start`
      #   with a block, yielding something that answers `request` with a
      #   `Net::HTTPGenericRequest` and returns its `Net::HTTPResponse`, as
      #   a Net::HTTP object does. {connection} with `timeout` when nil; a
      #   host's own sets its own bounds, so the two are not given together
      # @raise [ArgumentError] for a timeout that is not a positive finite
      #   number, a `connect` that does not answer `call`, or both given
      def initialize(timeout: nil, connect: nil)
        raise ArgumentError, "give timeout or connect, not both" if timeout && connect
        raise ArgumentError, "expected connect to answer call" unless connect.nil? || connect.respond_to?(:call)

        @timeout = timeout.nil? ? DEFAULT_TIMEOUT : checked_timeout(timeout)
        @connect = connect
        freeze
      end

      # The connection a {#call} for `uri` opens, not yet started: what the
      # host's `connect` answers for it, or {connection} with this
      # transport's timeout when the host gave none.
      #
      # @param uri [URI::HTTP] the URL requested
      # @return [Net::HTTP, Object] the connection
      def connect(uri) = @connect ? @connect.call(uri) : self.class.connection(uri, timeout: @timeout)

      # Makes `request` once and answers what came back.
      #
      # @param request [Request] the request
      # @return [Response] the response, whatever its status
      # @raise [TransportError] when no response came back
      # @raise [TypeError] for a request that is not a {Request}
      def call(request)
        raise TypeError, "expected a #{Request}, got #{request.class}" unless request.is_a?(Request)

        make(request)
      end

      private

      # The request made, every error but a {TransportError} raised as one
      # whose `cause` it is.
      def make(request)
        uri = target(request.url)
        response(exchange(uri, net_request(request, uri)))
      rescue TransportError
        raise
      rescue StandardError => e
        raise TransportError, "#{e.class}: #{e.message}"
      end

      def checked_timeout(timeout)
        return timeout if timeout.is_a?(Numeric) && timeout.real? && timeout.positive? && timeout.to_f.finite?

        raise ArgumentError, "expected timeout to be a positive finite number of seconds, got #{timeout.inspect}"
      end

      # The request's URL as an absolute `http` or `https` URI with a host.
      def target(url)
        uri = URI.parse(url)
        return uri if uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?

        raise TransportError, "not an absolute http or https URL: #{url}"
      rescue URI::InvalidURIError => e
        raise TransportError, "not a URL: #{e.message}"
      end

      # `request` as Net::HTTP's request for `uri`: the first header of a
      # name replaces Net::HTTP's default of that name, and a later one is
      # added to it.
      def net_request(request, uri)
        net = Net::HTTPGenericRequest.new(request.http_method, true, request.http_method != "HEAD", uri.request_uri)
        named = {}
        request.headers.each do |name, value|
          named.key?(name.downcase) ? net.add_field(name, value) : net[name] = value
          named[name.downcase] = true
        end
        net.body = request.body
        net
      end

      def exchange(uri, net_request)
        connect(uri).start { |http| http.request(net_request) }
      end

      def response(net_response)
        headers = net_response.to_hash.flat_map { |name, values| values.map { [name, _1] } }
        Response.new(status: Integer(net_response.code, 10), headers:, body: net_response.body.to_s)
      end
    end
  end
end
