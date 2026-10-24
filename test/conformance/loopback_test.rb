# frozen_string_literal: true

require "test_helper"
require "uri"
require_relative "runner"

# The charts the loopback tests drive.
module LoopbackCharts
  # A chart that sends ping to itself through the processor on each of its
  # first `count` entries of s0, re-entering s0 on each ping, then moves to
  # done.
  BOUNCING = <<~XML
    <datamodel><data id="n" expr="0"/></datamodel>
    <state id="s0">
      <onentry>
        <assign location="n" expr="n + 1"/>
        <if cond="n &lt;= %<count>d">
          <send event="ping" type="basichttp" targetexpr="_ioprocessors['basichttp']['location']"/>
        <else/>
          <raise event="e.done"/>
        </if>
      </onentry>
      <transition event="ping" target="s0"/>
      <transition event="e.done" target="done"/>
    </state>
    <state id="done"/>
  XML

  # A chart that sends to an address outside the front, which answers 404.
  MISSING = <<~XML
    <state id="s0">
      <onentry><send event="e.go" type="basichttp" target="http://elsewhere.invalid/x"/></onentry>
      <transition event="error.communication" target="pass"/>
      <transition event="*" target="fail"/>
    </state>
    <final id="pass"/><final id="fail"/>
  XML

  # A chart whose send through the processor carries data, beside a timer
  # due 1 ms later.
  DATA_AHEAD_OF_TIMER = <<~XML
    <state id="s0">
      <onentry>
        <send event="timeout" delay="1ms"/>
        <send event="e.go" type="basichttp" targetexpr="_ioprocessors['basichttp']['location']">
          <param name="n" expr="2"/>
        </send>
      </onentry>
      <transition event="e.go" cond="_event.data['n'] == 2" target="pass"/>
      <transition event="*" target="fail"/>
    </state>
    <final id="pass"/><final id="fail"/>
  XML
end

# The loopback front (Conformance::Loopback in test/conformance/loopback.rb):
# the reference front's status rule answered in memory, the Basic HTTP
# processor registered with it for a case that names it, the events it takes
# stepped into the session and the misses the processor reports reported
# back, within the exchange's round bound.
class LoopbackTest < Minitest::Test
  include LoopbackCharts

  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0" datamodel="predicator")
  URI_ = Statifier::BasicHTTP::EVENT_PROCESSOR
  SESSION = "w3c/x"
  BASE = Conformance::Loopback::BASE_URL
  LOCATION = "#{BASE}/#{SESSION}".freeze
  FORM = "application/x-www-form-urlencoded"
  SEND = %(<send event="e.go" type="basichttp" targetexpr="_ioprocessors['basichttp']['location']"/>)

  # A case naming the Basic HTTP processor around body, started in initial.
  def host_case(body, initial)
    { "id" => SESSION, "source" => %(<scxml #{ROOT} initial="s0">#{body}</scxml>), "initial_configuration" => initial,
      "steps" => [], "host" => { "event_io_processors" => [URI_] } }
  end

  def request(url: LOCATION, method: "POST", body: "_scxmleventname=e.go&n=2", type: FORM)
    Statifier::BasicHTTP::Request.new(http_method: method, url:, headers: [["Content-Type", type]], body:)
  end

  # A front answering for SESSION, and what it took.
  def loopback_front
    taken = []
    [Conformance::Loopback::Front.new(->(id) { id == SESSION }) { taken << _1 }, taken]
  end

  # What a fresh front answers `request` with, and what it took.
  def answered(request)
    front, taken = loopback_front
    [front.call(request), taken.map { [_1.name, _1.data] }]
  end

  # sabotage: answer 204 without calling @enqueue in Front#status; the
  # assert_equal on the event taken fails.
  def test_the_front_decodes_a_post_to_a_live_session_and_answers_no_content
    response, taken = answered(request)

    assert_equal 204, response.status
    assert_equal [["e.go", { "n" => 2 }]], taken
  end

  # sabotage: answer 400 for every refusal in Front#status; the assert_equal
  # on the 405 answer fails.
  def test_the_front_answers_a_method_other_than_post_405_with_allow
    response, taken = answered(request(method: "PUT"))

    assert_equal [405, [%w[allow POST]], []], [response.status, response.headers, taken]
  end

  # sabotage: answer 204 for an unknown session in Front#status (drop the
  # `@live.call(session_id)` test); the assert_equal on the statuses fails.
  def test_the_front_answers_a_request_that_forms_no_event_or_names_no_session
    statuses = [request(body: "n=%FF"), request(url: "#{BASE}/other"),
                request(url: "http://elsewhere.invalid/basichttp/#{SESSION}")].map { answered(_1) }

    assert_equal([[400, []], [404, []], [404, []]], statuses.map { |response, taken| [response.status, taken] })
  end

  # sabotage: drop the query from Front#addressed (answer `[path, nil]`); the
  # event is then named HTTP.POST and the assert_equal fails.
  def test_the_front_reads_the_query_string_after_the_session_id
    response, taken = answered(request(url: "#{LOCATION}?_scxmleventname=e.q", body: "x", type: "text/plain"))

    assert_equal [204, [%w[e.q x]]], [response.status, taken]
  end

  # sabotage: pass `transport: ->(_) { raise Statifier::BasicHTTP::TransportError }`
  # in Loopback::PROCESSORS; the wire then holds a miss and the assert_equal
  # on its arrival fails.
  def test_the_processor_is_registered_with_the_front_and_opens_no_socket
    wire = Conformance::Loopback::Wire.new(SESSION)
    types = Conformance::Drive::PROVIDED.fetch(URI_).call(wire)
    machine = Statifier.compile(%(<scxml #{ROOT}><state id="a"><onentry>#{SEND}</onentry></state></scxml>)).value

    Statifier.start(machine, session_id: SESSION, processors: types)

    assert_equal [URI_, "basichttp"], types.keys
    taken = wire.take

    assert_equal [:event], taken.map(&:kind)
    assert_equal(["e.go"], taken.map { _1.value.name })
  end

  # sabotage: set BASE_URL to "http://127.0.0.1/basichttp"; the assert fails.
  def test_the_front_answers_at_a_host_name_that_resolves_nowhere
    assert URI(BASE).host.end_with?(".invalid")
  end

  def bouncing(count) = host_case(format(BOUNCING, count:), %w[done])

  # sabotage: set MAX_EXCHANGE_ROUNDS to 99; the first assert_equal fails
  # (100 rounds then pass the bound).
  def test_an_exchange_takes_at_most_its_bound_of_rounds
    assert_equal 100, Conformance::Loopback::MAX_EXCHANGE_ROUNDS
    assert_equal :pass, Conformance::Drive.call(bouncing(100))
  end

  # sabotage: raise only when `round > MAX_EXCHANGE_ROUNDS + 1` in
  # Wire#exchange; the 101st round is then taken and the case passes.
  def test_a_case_past_the_round_bound_fails_naming_it
    assert_equal "the exchange with the loopback front did not settle within 100 rounds",
                 Conformance::Drive.call(bouncing(101))
  end

  # sabotage: drop the :missed arrival in Calls#arrive (answer `state` for
  # it); error.communication never arrives and the chart stays in s0.
  def test_a_miss_the_processor_reports_reaches_the_chart
    assert_equal :pass, Conformance::Drive.call(host_case(MISSING, %w[pass]))
  end

  # sabotage: step the arrival with `value.name` alone (no `data:`) in
  # Calls#handed; the guard on the data fails and the chart ends in fail.
  def test_an_event_the_front_takes_is_stepped_with_its_data_ahead_of_a_timer
    assert_equal :pass, Conformance::Drive.call(host_case(DATA_AHEAD_OF_TIMER, %w[pass]))
  end
end
