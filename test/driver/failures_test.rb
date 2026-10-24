# frozen_string_literal: true

require "test_helper"
require_relative "driver_helper"

# The charts the failed-send tests drive.
module FailureCharts
  # A send that fails on entering `a`; the error's transition queues e.go,
  # which moves the chart to `b`.
  QUEUED = <<~XML
    <state id="a">
      <onentry><send type="x-rec" target="t" event="x" id="n"/></onentry>
      <transition event="error.communication"><send event="e.go"/></transition>
      <transition event="e.go" target="b"/>
    </state>
    <state id="b"/>
  XML

  # A registered send, then an internal event raised again on every round.
  LOOPING = <<~XML
    <state id="a">
      <onentry><send type="x-rec" target="t" event="x" id="n"/><raise event="loop"/></onentry>
      <transition event="loop"><raise event="loop"/></transition>
    </state>
  XML

  # A registered send made again on every error.communication.
  RESENDING = <<~XML
    <state id="a">
      <onentry><send type="x-rec" target="t" event="x" id="n"/></onentry>
      <transition event="error.communication"><send type="x-rec" target="t" event="x" id="n"/></transition>
    </state>
  XML
end

# A failed send: reported later through Statifier.report_send_failed, or
# answered from the processor's deliver as a DeliveryFailure, each raising
# error.communication with the send's id.
class FailuresTest < Minitest::Test
  include FailureCharts
  include DriverHelper

  U = Predicator::UNDEFINED

  # A processor that records what it is handed and answers `answer` from
  # deliver.
  class Answering < Recorder
    def initialize(answer)
      super()
      @answer = answer
    end

    def deliver(...)
      super
      @answer
    end
  end

  # Two registered sends on entering `a`, one its author names and one it
  # does not, and the error's fields logged as `a` takes it.
  CHART = <<~XML
    <state id="a">
      <onentry>
        <send type="x-rec" target="t" event="named" id="n"/>
        <send type="x-rec" target="t" event="generated"/>
      </onentry>
      <transition event="error.communication">
        <log label="error" expr="[_event.name, _event.type, _event.sendid, _event.data]"/>
      </transition>
      <transition event="e.go" target="b"/>
      <transition event="e.end" target="f"/>
    </state>
    <state id="b"/>
    <final id="f"/>
  XML

  def setup
    @recorder = Recorder.new
    @processors = { "x-rec" => @recorder }
    @machine = machine(CHART)
    @started = moved(Statifier.start(@machine, session_id: "s1", processors: @processors))
  end

  # `body` started under the processor `processor` for x-rec: the machine,
  # the processors and what the start answered.
  def started(body, processor = Recorder.new, **)
    machine = machine(body)
    processors = { "x-rec" => processor }
    [machine, processors, moved(Statifier.start(machine, session_id: "s1", processors:, **))]
  end

  def handed(index) = @recorder.calls.select { _1.first == :deliver }.fetch(index)[1]

  def report(send, state = @started.state, **)
    Statifier.report_send_failed(@machine, state, send, processors: @processors, **)
  end

  # sabotage: write the send id only when its author named it in
  # Delivery.failed (`sendid: nil` for a generated id); the assert_equal on
  # the generated send's log fails.
  def test_a_report_raises_error_communication_with_the_send_id_whether_or_not_the_author_named_it
    named = moved(report(handed(0), reason: "refused"))
    generated = moved(report(handed(1)))

    assert_equal [["error", ["error.communication", "platform", "n", U]]], logs(named)
    assert_equal [["error", ["error.communication", "platform", handed(1).send_id, U]]], logs(generated)
    refute_nil handed(1).send_id
  end

  # sabotage: drop the drain in Calls.report_send_failed (answer the work
  # after the perform alone); the assert_equal on the configuration fails
  # (e.go, queued by the error's transition, is never taken).
  def test_a_report_runs_the_chart_and_then_takes_its_external_queue
    recorder = Recorder.new
    machine, processors, started = started(QUEUED, recorder)
    reported = moved(Statifier.report_send_failed(machine, started.state, recorder.calls.first[1], processors:))

    assert_equal %w[b], active(reported)
  end

  # sabotage: drop the `running` check in Calls.report_send_failed; the
  # assert_equal on the error fails (the stopped chart answers a move).
  def test_a_report_to_a_stopped_chart_is_refused
    stopped = step(@started, "e.end", processors: @processors)

    assert_equal :not_running, report(handed(0), stopped.state).error
  end

  # sabotage: drop the `halted` check in Calls.report_send_failed; the
  # assert_equal on the error fails (the halted chart takes the report).
  def test_a_report_to_a_chart_a_round_budget_halted_is_refused
    recorder = Recorder.new
    machine, processors, halted = started(LOOPING, recorder, max_macrostep_rounds: 5)
    send = recorder.calls.first[1]

    assert_equal :budget_exhausted, halted.state.halted
    assert_equal :halted, Statifier.report_send_failed(machine, halted.state, send, processors:).error
  end

  # sabotage: answer the options whatever the state's machine is in
  # Checks.report; the assert_raises naming another machine fails.
  def test_a_report_checks_the_chart_it_names
    send = handed(0)
    other = machine("<state id='z'/>")

    assert_raises(TypeError) { Statifier.report_send_failed(:chart, @started.state, send) }
    assert_raises(ArgumentError) { Statifier.report_send_failed(other, @started.state, send, processors: @processors) }
    assert moved(Statifier.report_send_failed(machine(CHART), @started.state, send, processors: @processors))
  end

  # sabotage: drop the send's check in Checks.report; the first
  # assert_raises fails (the symbol reaches the routing and raises
  # NoMethodError).
  def test_a_report_checks_the_send_the_options_and_the_processors
    assert_raises(TypeError) { report(:send) }
    assert_raises(ArgumentError) { report(handed(0), unknown: 1) }
    assert_raises(ArgumentError) { Statifier.report_send_failed(@machine, @started.state, handed(0)) }
  end

  # sabotage: answer `[work, []]` whatever deliver answered in
  # Delivery.hand_off; the assert_equal on the logs fails (no error is
  # raised).
  def test_a_delivery_failure_from_deliver_raises_the_same_event_within_the_call
    failing = Answering.new(Statifier::Driver::DeliveryFailure.new(reason: "no route"))
    _, _, started = started(CHART, failing)
    generated = failing.calls[1][1].send_id

    assert_equal [["error", ["error.communication", "platform", "n", U]],
                  ["error", ["error.communication", "platform", generated, U]]], logs(started)
    assert_nil Statifier::Driver::DeliveryFailure.new.reason
  end

  # sabotage: count each delivery twice in Routing.counted (`+ 2`); the
  # assert_equal on the processor's calls fails (the chart halts after
  # fewer sends).
  def test_a_chart_that_sends_again_on_every_failure_halts_on_its_round_budget
    failing = Answering.new(Statifier::Driver::DeliveryFailure.new)
    _, _, started = started(RESENDING, failing, max_macrostep_rounds: 3)

    assert_equal :budget_exhausted, started.state.halted
    assert_equal 4, failing.calls.size
  end
end
