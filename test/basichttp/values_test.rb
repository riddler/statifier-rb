# frozen_string_literal: true

require "test_helper"
require_relative "basichttp_helper"

# Statifier::BasicHTTP::Request and Response: the values a transport takes
# and answers, frozen deeply, built from copies of what a caller passes.
class BasicHTTPValuesTest < Minitest::Test
  include BasicHTTPHelper

  # sabotage: return value unfrozen in Values.string; the shareable assertion fails.
  def test_a_request_is_a_deeply_frozen_value
    built = request(url: +"http://localhost:8080/s1", headers: [[+"x-a", +"1"]], body: +"e.go")

    assert_equal ["POST", "http://localhost:8080/s1", [%w[x-a 1]], "e.go"],
                 [built.http_method, built.url, built.headers, built.body]
    assert Ractor.shareable?(built), "a request is frozen deeply"
  end

  # sabotage: freeze value in place in Values.string; the host's strings come back frozen.
  def test_a_request_copies_what_it_is_built_from_and_freezes_none_of_it
    url = +"http://localhost:8080/s1"
    pair = [+"x-a", +"1"]
    body = +"e.go"
    request(url:, headers: [pair], body:)

    assert_equal [false, false, false, false], [url, body, pair, pair[0]].map(&:frozen?)
  end

  # sabotage: default headers: to [["x-a", "1"]] in Request#initialize; the headers are not empty.
  def test_a_request_defaults_to_no_headers_and_an_empty_body
    built = B::Request.new(http_method: "GET", url: "http://localhost/")

    assert_equal [[], ""], [built.headers, built.body]
  end

  # sabotage: drop the TOKEN check in Values.token; no ArgumentError is raised.
  def test_a_request_refuses_a_method_or_header_name_that_is_not_a_token
    assert_raises(ArgumentError) { request(http_method: "PO ST") }
    assert_raises(ArgumentError) { request(http_method: "") }
    assert_raises(ArgumentError) { request(headers: [["x a", "1"]]) }
  end

  # sabotage: drop the CR, LF and NUL check in Values.header; no ArgumentError is raised.
  def test_a_request_refuses_a_header_value_that_could_split_the_message
    ["1\r\nx-b: 2", "1\n", "1\0"].each do |value|
      assert_raises(ArgumentError, value.inspect) { request(headers: [["x-a", value]]) }
    end
  end

  # sabotage: test respond_to?(:map) for is_a?(Array) in Values.headers; the Hash is taken and no TypeError is raised.
  def test_a_request_refuses_members_of_the_wrong_kind
    assert_raises(TypeError) { request(url: :url) }
    assert_raises(TypeError) { request(body: nil) }
    assert_raises(TypeError) { request(headers: { "x-a" => "1" }) }
    assert_raises(TypeError) { request(headers: [["x-a"]]) }
    assert_raises(TypeError) { request(headers: [["x-a", 1]]) }
  end

  # sabotage: drop the range check in Response#initialize; no ArgumentError is raised.
  def test_a_response_holds_a_status_from_one_hundred_to_five_hundred_ninety_nine
    assert_equal 599, B::Response.new(status: 599).status
    assert_raises(ArgumentError) { B::Response.new(status: 99) }
    assert_raises(ArgumentError) { B::Response.new(status: 600) }
    assert_raises(TypeError) { B::Response.new(status: "200") }
  end

  # sabotage: pass headers through uncopied in Response#initialize; the shareable assertion fails.
  def test_a_response_is_a_deeply_frozen_copy_of_what_it_is_built_from
    pair = [+"content-type", +"text/plain"]
    body = +"ok"
    built = B::Response.new(status: 200, headers: [pair], body:)

    assert_equal [200, [%w[content-type text/plain]], "ok"], [built.status, built.headers, built.body]
    assert Ractor.shareable?(built), "a response is frozen deeply"
    assert_equal [false, false], [pair, body].map(&:frozen?)
  end

  # sabotage: default body: to "x" in Response#initialize; the body is not empty.
  def test_a_response_defaults_to_no_headers_and_an_empty_body
    built = B::Response.new(status: 204)

    assert_equal [[], ""], [built.headers, built.body]
  end

  # A transport is any callable of the contract: here a lambda in place of
  # the default one.
  def test_a_lambda_is_a_transport
    transport = ->(req) { B::Response.new(status: 202, body: req.body) }

    answered = transport.call(request(body: "e.go"))

    assert_equal [202, "e.go"], [answered.status, answered.body]
  end
end
