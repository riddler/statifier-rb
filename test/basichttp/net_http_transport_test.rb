# frozen_string_literal: true

require "test_helper"
require_relative "basichttp_helper"

# Statifier::BasicHTTP::NetHTTPTransport, the default transport, driven
# against a local test double below Net::HTTP (BasicHTTPHelper::Connection):
# Net::HTTP builds, writes and reads each message, and no socket is opened.
class NetHTTPTransportTest < Minitest::Test
  include BasicHTTPHelper

  CREATED = "HTTP/1.1 201 Created\r\nContent-Type: text/plain\r\nSet-Cookie: a=1\r\n" \
            "Set-Cookie: b=2\r\nContent-Length: 2\r\n\r\nok"

  # sabotage: drop `net.body = request.body` in net_request; the wire lacks the body.
  def test_the_request_goes_on_the_wire_as_it_was_built
    connection = Connection.new
    headers = [%w[content-type text/plain], %w[scxml-send-key k1]]
    transport_over(connection).call(request(url: "http://localhost:8080/s1?q=1", headers:, body: "e.go"))
    head, body = connection.wire.split("\r\n\r\n", 2)
    lines = head.split("\r\n")

    assert_equal "POST /s1?q=1 HTTP/1.1", lines.first
    assert_equal ["Content-Type: text/plain", "Scxml-Send-Key: k1", "Content-Length: 4"],
                 lines.grep(/\A(Content-Type|Scxml-Send-Key|Content-Length):/)
    assert_equal "e.go", body
  end

  # sabotage: connect to a fixed URI in exchange; the URI recorded is not the request's.
  def test_one_connection_is_opened_for_the_request_url
    connection = Connection.new
    uris = []
    transport_over(connection, uris).call(request(url: "http://localhost:8080/s1"))

    assert_equal([["localhost", 8080, "http"]], uris.map { [_1.host, _1.port, _1.scheme] })
    assert_equal 1, connection.started
  end

  # sabotage: always add_field in net_request; the wire carries Net::HTTP's default user-agent too.
  def test_a_header_replaces_the_default_of_its_name_and_a_repeat_adds_to_it
    connection = Connection.new
    transport_over(connection).call(request(headers: [%w[user-agent t1], %w[x-a 1], %w[X-A 2]]))
    lines = connection.wire.split("\r\n\r\n", 2).first.split("\r\n")

    assert_equal ["User-Agent: t1"], lines.grep(/\AUser-Agent:/)
    assert_equal ["X-A: 1, 2"], lines.grep(/\AX-A:/)
  end

  # sabotage: drop the flat_map over each name's values in response (keep the first); set-cookie loses b=2.
  def test_the_response_is_answered_with_its_status_headers_and_body
    answered = transport_over(Connection.new(CREATED)).call(request)

    assert_equal 201, answered.status
    assert_equal [%w[content-type text/plain], %w[set-cookie a=1], %w[set-cookie b=2], %w[content-length 2]],
                 answered.headers
    assert_equal "ok", answered.body
    assert Ractor.shareable?(answered), "the response is frozen deeply"
  end

  # sabotage: clamp the status to 200..299 in response; the 503 is answered as 299.
  def test_a_status_outside_2xx_is_a_response_not_an_error
    answered = transport_over(Connection.new("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n"))
               .call(request)

    assert_equal [503, ""], [answered.status, answered.body]
  end

  # sabotage: answer a nil body as "none" in response; the body is not empty.
  def test_a_response_with_no_body_is_answered_with_an_empty_one
    answered = transport_over(Connection.new("HTTP/1.1 204 No Content\r\n\r\n")).call(request)

    assert_equal [204, ""], [answered.status, answered.body]
  end

  # sabotage: drop the `rescue StandardError` clause in make; the connection's own error escapes.
  def test_an_error_while_connecting_or_exchanging_is_a_transport_error_with_its_cause
    [Errno::ECONNREFUSED.new("connect(2)"), Net::OpenTimeout.new("execution expired"), EOFError.new("end of file")]
      .each do |error|
        raised = assert_raises(B::TransportError) { transport_over(Connection.new(error: error)).call(request) }

        assert_same error, raised.cause
        assert_includes raised.message, error.class.name
      end
  end

  # sabotage: drop the 100..599 check in Response#initialize; the 600 status is answered.
  def test_a_status_line_outside_100_to_599_is_a_transport_error
    assert_raises(B::TransportError) do
      transport_over(Connection.new("HTTP/1.1 600 Odd\r\nContent-Length: 0\r\n\r\n")).call(request)
    end
  end

  # sabotage: return uri unchecked in target; ftp and hostless URLs reach the connection.
  def test_a_url_that_is_not_an_absolute_http_url_opens_no_connection
    uris = []
    ["ftp://localhost/s1", "http://", "/s1", "http://local host/", "localhost:8080"].each do |url|
      assert_raises(B::TransportError, url) { transport_over(Connection.new, uris).call(request(url:)) }
    end

    assert_empty uris
  end

  # sabotage: drop the Request check in call; a NoMethodError becomes a TransportError instead.
  def test_a_request_that_is_not_a_request_value_is_a_type_error
    assert_raises(TypeError) { transport_over(Connection.new).call({ http_method: "POST" }) }
  end

  # sabotage: permit a response body for every method in net_request; the HEAD response's body is read.
  def test_a_head_request_reads_no_body
    answered = transport_over(Connection.new("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"))
               .call(request(http_method: "HEAD"))

    assert_equal [200, ""], [answered.status, answered.body]
  end

  # sabotage: drop `use_ssl =` in connection; the https connection is not TLS.
  def test_the_default_connection_is_an_unstarted_net_http_with_its_bounds
    https = B::NetHTTPTransport.connection(URI("https://localhost:8443/s1"), timeout: 2)

    assert_instance_of Net::HTTP, https
    assert_equal ["localhost", 8443, true, false], [https.address, https.port, https.use_ssl?, https.started?]
    assert_equal [2, 2, 2, 2], [https.open_timeout, https.ssl_timeout, https.write_timeout, https.read_timeout]
  end

  # sabotage: set use_ssl = true unconditionally in connection; the http connection is TLS.
  def test_the_default_connection_for_http_is_plain_with_the_default_bound
    http = B::NetHTTPTransport.connection(URI("http://localhost/s1"))

    assert_equal [80, false, 5], [http.port, http.use_ssl?, http.read_timeout]
  end

  # sabotage: drop `timeout: @timeout` from connect; the connection takes the default 5.
  def test_the_default_connect_uses_the_timeout_given
    connection = B::NetHTTPTransport.new(timeout: 0.5).connect(URI("http://localhost/"))

    assert_equal [0.5, false], [connection.read_timeout, connection.started?]
    assert_equal 5, B::NetHTTPTransport.new.connect(URI("http://localhost/")).read_timeout
  end

  # sabotage: ignore @connect in connect; the host's connection is not the one answered.
  def test_a_host_connect_answers_the_connection
    connection = Connection.new

    assert_same connection, transport_over(connection).connect(URI("http://localhost/"))
  end

  # sabotage: drop the both-given check in initialize; no ArgumentError is raised.
  def test_the_options_are_checked
    assert_raises(ArgumentError) { B::NetHTTPTransport.new(timeout: 1, connect: ->(_uri) {}) }
    assert_raises(ArgumentError) { B::NetHTTPTransport.new(connect: :not_callable) }
    [0, -1, Float::INFINITY, Float::NAN, "5", Complex(1, 1)].each do |timeout|
      assert_raises(ArgumentError, timeout.inspect) { B::NetHTTPTransport.new(timeout:) }
    end
    assert_predicate B::NetHTTPTransport.new, :frozen?
  end
end
