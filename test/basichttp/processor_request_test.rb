# frozen_string_literal: true

require "test_helper"
require_relative "processor_helper"

# The request each send the processor is handed becomes (Outbound.request)
# and the send key it carries, as tables of rows the reference's processor
# builds alike.
class BasicHTTPProcessorRequestTest < Minitest::Test
  include ProcessorHelper

  OUTBOUND = Statifier::BasicHTTP.const_get(:Outbound)

  # The request a send becomes: [send fields, url, content type, body].
  REQUESTS = [
    [{ data: { "Var1" => 2, "name" => "two words" } }, TARGET, FORM, "_scxmleventname=ping&Var1=2&name=two+words"],
    [{ data: { "b" => 1, "a" => 2 } }, TARGET, FORM, "_scxmleventname=ping&a=2&b=1"],
    [{ data: U }, TARGET, FORM, "_scxmleventname=ping"],
    [{ event: nil, data: U }, TARGET, FORM, ""],
    [{ data: "some content" }, "#{TARGET}?_scxmleventname=ping", "text/plain", "some content"],
    [{ target: "#{TARGET}?a=1", data: "x" }, "#{TARGET}?a=1&_scxmleventname=ping", "text/plain", "x"],
    [{ event: nil, data: 42 }, TARGET, "text/plain", "42"],
    [{ data: ["s", U] }, "#{TARGET}?_scxmleventname=ping", "text/plain", '["s",null]'],
    [{ data: { "null" => nil, "unbound" => U, "flag" => true, "list" => [1, 2] } }, TARGET, FORM,
     "_scxmleventname=ping&flag=true&list=%5B1%2C2%5D&null=null&unbound="],
    [{ event: "a b&c", data: "body" }, "#{TARGET}?_scxmleventname=a+b%26c", "text/plain", "body"],
    [{ event: 7, data: U }, TARGET, FORM, "_scxmleventname=7"],
    [{ event: nil, data: { "_scxmleventname" => "e.go" } }, TARGET, FORM, "_scxmleventname=e.go"]
  ].freeze

  # sabotage: always use `?` in with_query; the target-with-query row carries two.
  def test_a_send_becomes_the_request_the_reference_builds
    REQUESTS.each do |fields, url, content_type, body|
      request = OUTBOUND.request("s1", send_effect(**fields))

      assert_equal [url, content_type, body], [request.url, request.headers.assoc("content-type").last, request.body],
                   fields.inspect
      assert_equal "POST", request.http_method
    end
  end

  # The send key: [send fields, session id, key].
  KEYS = [
    [{}, "s1", "s1/send_1/1/1/0/3/onentry.2.0/1"],
    [{ send_id: "a/b c", owner: { kind: :transition, t_index: 4 }, macrostep: 7, microstep: 2, round: 1, ordinal: 9 },
     "sess/x", "sess%2Fx/a%2Fb%20c/7/2/1/3/transition.4/9"],
    [{ owner: { kind: :onexit, state_index: 5, ordinal: 1 }, ordinal: nil }, "s1", "s1/send_1/1/1/0/3/onexit.5.1/"],
    [{ owner: { kind: :finalize, state_index: 3, invoke_index: 1 } }, "s1", "s1/send_1/1/1/0/3/finalize.3.1/1"]
  ].freeze

  # sabotage: drop the ordinal from send_key; every row has seven fields.
  def test_every_request_carries_the_send_key_the_reference_spells
    KEYS.each do |fields, session_id, key|
      assert_equal key, OUTBOUND.request(session_id, send_effect(**fields)).headers.assoc("scxml-send-key").last
    end
    assert_equal "s1/send_1/1/1/0/3/onentry.2.0/1", OUTBOUND.send_key("s1", delayed_effect)
  end
end
