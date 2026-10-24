# frozen_string_literal: true

require "test_helper"
require_relative "processor_helper"

# Statifier::BasicHTTP::Processor#deliver and its options: the request
# handed to the transport, the miss handed to the host, the _ioprocessors
# entry and the send types.
class BasicHTTPProcessorTest < Minitest::Test
  include ProcessorHelper

  # sabotage: answer nil in place of post in deliver; the wire records no request.
  def test_a_send_is_handed_to_the_transport_once_and_a_success_reports_nothing
    wire = Wire.new(status: 200)
    misses = []

    assert_nil processor(wire, misses).deliver(send_effect(data: { "a" => 1 }), nil, context)
    assert_equal([[TARGET, "_scxmleventname=ping&a=1"]], wire.requests.map { [_1.url, _1.body] })
    assert_empty misses
  end

  # sabotage: test 200..399 in post; the 302 is not reported.
  def test_a_status_outside_2xx_is_reported_with_its_response
    [199, 302, 404, 503].each do |status|
      misses = []
      send = send_effect

      assert_nil processor(Wire.new(status:), misses).deliver(send, nil, context)
      assert_equal([["s1", :http_status, status]], misses.map { [_1.session_id, _1.reason, _1.detail.status] })
      assert_same send, misses.first.effect
    end
  end

  # sabotage: answer a fresh TransportError in place of the error raised in exchange; the detail is not the same.
  def test_a_transport_that_raises_is_reported_with_its_error
    error = B::TransportError.new("connection refused")
    misses = []

    assert_nil processor(Wire.new(error:), misses).deliver(send_effect, nil, context)
    assert_equal [:transport_error], misses.map(&:reason)
    assert_same error, misses.first.detail
  end

  # sabotage: answer a TransportError in place of the TypeError in exchange; the detail's class differs.
  def test_a_transport_that_answers_no_response_is_reported_as_a_type_error
    misses = []
    processor(->(_request) { :ok }, misses).deliver(send_effect, nil, context)

    assert_equal([[:transport_error, TypeError]], misses.map { [_1.reason, _1.detail.class] })
  end

  # sabotage: drop the target.nil? clause in deliver; the send is reported as an invalid target instead.
  def test_a_send_with_no_target_fails_within_the_call_and_makes_no_request
    wire = Wire.new
    misses = []
    answered = processor(wire, misses).deliver(send_effect(target: nil), nil, context)

    assert_equal Statifier::Driver::DeliveryFailure.new(reason: :no_target), answered
    assert_empty wire.requests
    assert_empty misses
  end

  # sabotage: report a non-String target as :transport_error in deliver; the reason differs.
  def test_a_target_that_is_not_a_string_is_reported_and_makes_no_request
    wire = Wire.new
    misses = []
    processor(wire, misses).deliver(send_effect(target: 42), nil, context)

    assert_equal([[:invalid_target, 42]], misses.map { [_1.reason, _1.detail] })
    assert_empty wire.requests
  end

  # sabotage: drop the SendDelayed clause in deliver; the delayed send is posted at once.
  def test_a_delayed_send_is_reported_as_held_by_no_timer_and_makes_no_request
    wire = Wire.new
    misses = []
    processor(wire, misses).deliver(delayed_effect, nil, context)

    assert_equal([[:no_timer, nil]], misses.map { [_1.reason, _1.detail] })
    assert_empty wire.requests
  end

  # sabotage: drop the `/` in ioprocessors_entry; the location runs the session id on.
  def test_the_location_is_the_base_url_a_slash_and_the_session_id
    entry = processor.ioprocessors_entry(B::SHORT_TYPE, context)

    assert_equal({ "location" => "http://localhost:8080/scxml/s1" }, entry)
    assert Ractor.shareable?(entry)
  end

  # sabotage: name only EVENT_PROCESSOR in send_types; the short type is missing.
  def test_the_send_types_name_the_processor_under_its_uri_and_its_short_type
    http = processor

    assert_equal [B::EVENT_PROCESSOR, "basichttp"], http.send_types.keys
    assert(http.send_types.values.all? { _1.equal?(http) })
    assert_equal "http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor", B::EVENT_PROCESSOR
  end

  # sabotage: freeze base_url in place in address; the host's string comes back frozen.
  def test_the_options_are_checked_and_the_base_url_copied
    base_url = +"http://localhost/scxml"
    http = B::Processor.new(base_url:, report: ->(_) {})

    assert_equal [false, true, true], [base_url.frozen?, http.base_url.frozen?, http.frozen?]
    [[TypeError, { base_url: nil }], [ArgumentError, { base_url: "" }], [ArgumentError, { report: :not_callable }],
     [ArgumentError, { transport: :no }]].each do |error, options|
      assert_raises(error, options.inspect) { B::Processor.new(base_url: "http://h", report: ->(_) {}, **options) }
    end
  end

  # sabotage: default transport: to a lambda answering 204 in initialize; no transport error is reported.
  def test_the_default_transport_is_net_http
    misses = []
    B::Processor.new(base_url: "http://h", report: misses.method(:<<)).deliver(send_effect(target: "ftp://h/s1"), nil,
                                                                               context)

    assert_equal([[:transport_error, B::TransportError]], misses.map { [_1.reason, _1.detail.class] })
    assert_includes misses.first.detail.message, "not an absolute http or https URL"
  end
end
