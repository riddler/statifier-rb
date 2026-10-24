# frozen_string_literal: true

require "test_helper"
require "statifier/basichttp"

# Statifier::BasicHTTP.decode: one HTTP request to the event it carries, or
# the refusal, as a table of rows the reference's decoder answers alike.
class BasicHTTPDecodeTest < Minitest::Test
  B = Statifier::BasicHTTP
  U = Predicator::UNDEFINED
  FORM = "application/x-www-form-urlencoded"
  KEY = "s1/send_1/1/1/0/3/onentry.2.0/1"

  def decode(method: "POST", content_type: FORM, body: "", query: nil, send_key: nil)
    B.decode(method:, content_type:, body:, query:, send_key:)
  end

  # A request and its event: [request, name, data].
  EVENTS = [
    [{ body: "_scxmleventname=e.go&n=2&s=hi+there" }, "e.go", { "n" => 2, "s" => "hi there" }],
    [{ body: "_scxmleventname=b1", query: "_scxmleventname=q1&_scxmleventname=q2" }, "q1", U],
    [{ body: "n=2", query: "n=1&m=3" }, "HTTP.POST", { "n" => 2, "m" => 3 }],
    [{ method: "post", content_type: "Application/X-WWW-Form-Urlencoded; charset=utf-8", body: "a=1&a=2" },
     "HTTP.POST", { "a" => 2 }],
    [{ body: "b=%5B1%2C2%5D&c=%7B%22k%22%3A1%7D&t=true&f=1.50&q='x'&w=two++words" }, "HTTP.POST",
     { "b" => [1, 2], "c" => { "k" => 1 }, "t" => true, "f" => 1.5, "q" => "x", "w" => "two words" }],
    [{ body: "a&&b=&=c" }, "HTTP.POST", { "a" => U, "b" => U, "" => "c" }],
    [{ body: "" }, "HTTP.POST", U],
    [{ content_type: "text/plain", body: "  some   content \n here ", query: "_scxmleventname=named&x=1" }, "named",
     "some content here"],
    [{ content_type: "application/json", body: '{"a": 1}' }, "HTTP.POST", { "a" => 1 }],
    [{ content_type: "application/json", body: "[1, \"two\"]" }, "HTTP.POST", [1, "two"]],
    [{ content_type: nil, body: "42" }, "HTTP.POST", 42],
    [{ content_type: nil, body: "null" }, "HTTP.POST", nil],
    [{ content_type: nil, body: "" }, "HTTP.POST", U],
    [{ send_key: KEY }, "HTTP.POST", U]
  ].freeze

  # sabotage: take the last _scxmleventname in Decode.event (named.last); the q1 row reads q2.
  def test_a_request_decodes_to_the_event_the_reference_forms
    EVENTS.each do |request, name, data|
      event = decode(**request).value

      assert_equal [name, data], [event.name, event.data], request.inspect
      assert_equal [:external, B::EVENT_PROCESSOR, nil, nil], [event.type, event.origintype, event.origin, event.sendid]
    end
  end

  # sabotage: answer the event unfrozen (drop Frozen.copy) in Decode.event; the shareable assertion fails.
  def test_the_event_is_deeply_frozen
    assert Ractor.shareable?(decode(body: "a=%5B1%5D").value)
  end

  # A request and its refusal: [request, reason, detail].
  REFUSALS = [
    [{ method: "GET" }, :method_not_allowed, "GET"],
    [{ method: "PUT", content_type: "text/plain", body: "x" }, :method_not_allowed, "PUT"],
    [{ body: "a=%E9" }, :not_utf8, :body],
    [{ content_type: nil, query: "a=%E9" }, :not_utf8, :query],
    [{ content_type: nil, body: "caf\xE9".b }, :not_utf8, :body],
    [{ send_key: "s1/send_1/1/1/0/3/onentry.2.0" }, :malformed_send_key, "s1/send_1/1/1/0/3/onentry.2.0"],
    [{ send_key: "s1/%E9/1/1/0/3/onentry.2.0/1" }, :malformed_send_key, "s1/%E9/1/1/0/3/onentry.2.0/1"],
    [{ send_key: "s1/send_1/1/1/0/3/onentry.2.0/1/" }, :malformed_send_key, "s1/send_1/1/1/0/3/onentry.2.0/1/"],
    [{ method: "GET", query: "a=%E9", send_key: "x" }, :method_not_allowed, "GET"],
    [{ query: "a=%E9", body: "a=%E9" }, :not_utf8, :query],
    [{ body: "a=%E9", send_key: "x" }, :not_utf8, :body]
  ].freeze

  # sabotage: split the send key without the -1 limit in send_key?; the trailing-slash row is accepted.
  def test_a_request_the_reference_refuses_is_refused_in_its_order
    REFUSALS.each do |request, reason, detail|
      decoded = decode(**request)

      assert_nil decoded.value
      assert_equal B::Refusal.new(reason:, detail:), decoded.error, request.inspect
    end
  end

  # sabotage: let a nil body through in Decode.checked; a NoMethodError replaces the TypeError.
  def test_an_argument_of_the_wrong_kind_raises
    assert_raises(TypeError) { decode(method: nil) }
    assert_raises(TypeError) { decode(body: nil) }
    assert_raises(TypeError) { decode(query: 1) }
    assert_raises(TypeError) { decode(content_type: :form) }
    assert_raises(TypeError) { decode(send_key: 1) }
  end

  # sabotage: freeze the body in place in Decode.body (body.freeze); the host's body comes back frozen.
  def test_the_request_strings_are_read_and_never_frozen
    body = +"a=1"
    method = +"POST"
    decode(method:, body:)

    assert_equal [false, false], [body.frozen?, method.frozen?]
  end
end
