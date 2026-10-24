# frozen_string_literal: true

require "test_helper"
require_relative "invoke_helper"

# The driver's invocations: what a child starts with and inherits, its
# timers, its own children, and a position taken while it lives.
class DriverInvokeInheritTest < Minitest::Test
  include DriverInvokeHelper

  REFUSED = <<~XML
    <state id="a">
      <invoke id="t" type="other"/>
      <invoke id="v"><content expr="1 + 1"/></invoke>
      <invoke id="n"/>
      <transition event="error.*"><log label="err" expr="[_event.name, _event.type]"/></transition>
    </state>
  XML
  SEEDED = <<~XML
    <datamodel><data id="p" expr="0"/></datamodel>
    <state id="x"><onentry><log label="p" expr="[p, In('x')]"/><log label="q" expr="q"/></onentry></state>
  XML
  GRANDCHILD = %(<state id="g"><onentry><send target="#_parent" event="hi"/></onentry></state>)

  # sabotage: skip the type check in Invocations.start (`unless true`); the
  # assert_equal on the logs fails.
  def test_another_type_raises_error_execution_and_content_that_is_not_markup_error_communication
    started = start(REFUSED)
    expected = [["err", %w[error.execution platform]], ["err", %w[error.communication platform]],
                ["err", %w[error.communication platform]]]

    assert_equal expected, logs(started)
    assert_empty started.state.invocations
  end

  # sabotage: answer `params` unfiltered in Invocations.seed; the
  # assert_equal on the child's logs fails.
  def test_the_child_s_datamodel_is_seeded_with_the_params_its_root_data_names
    started = start(invoking(SEEDED, extra: %(<param name="p" expr="7"/><param name="q" expr="8"/>)))

    assert_equal [["p", [7, true]]], child_logs(started, "s1.c")
  end

  # sabotage: start the child with `send_types: nil` in
  # Invocations.start_options; the assert_equal on the processor's calls
  # fails.
  def test_the_child_inherits_the_registered_send_types_with_its_own_session_id
    recorder = Recorder.new
    child = %(<state id="x"><onentry><send type="x-test" event="out" target="anywhere"/></onentry></state>)
    start(invoking(child), processors: { "x-test" => recorder })
    calls = recorder.calls.map { [_1[0], _1[1].event, _1[3].session_id] }

    assert_equal [[:deliver, "out", "s1.c"]], calls
  end

  # sabotage: drop the children's timers from Calls.pending; the
  # assert_equal on the configuration fails.
  def test_a_child_s_delayed_send_fires_on_its_parent_s_clock
    child = %(<state id="x"><onentry><send target="#_parent" event="late" delay="50ms"/></onentry></state>)
    started = start(invoking(child, %(<transition event="late" target="b"/>), %(<state id="b"/>)))

    assert_equal %w[a], active(advance(started, 49))
    assert_equal %w[b], active(advance(advance(started, 49), 1))
  end

  # sabotage: report every effect bare in Work#report; the assert_equal on
  # the session ids fails.
  def test_a_child_s_own_child_is_reported_under_its_own_session_id
    child = %(<state id="x">#{invoke(GRANDCHILD, %(id="g"))}<transition event="hi" target="y"/></state>
              <state id="y"><onentry><send target="#_parent" event="hi"/></onentry></state>)
    started = start(invoking(child, %(<transition event="hi" target="b"/>), %(<state id="b"/>)))

    assert_equal %w[s1.c s1.c.g], started.effects.grep(E::Child).map(&:session_id).uniq.sort
    assert_equal %w[b], active(started)
  end

  # sabotage: start the child with `trace: false` in
  # Invocations.start_options; the assert_equal on the child's trace fails.
  def test_the_child_starts_with_its_parent_s_trace_flag
    traced = start(invoking(%(<state id="x"/>)), trace: true)
    plain = start(invoking(%(<state id="x"/>)))

    assert_equal([1, 0], [traced, plain].map { child_effects(_1, "s1.c").grep(T::EntrySet).size })
  end

  # sabotage: export `"active_invocations" => []` in Position.exported; the
  # assert_equal on the position fails.
  def test_a_position_taken_with_a_live_child_carries_the_invocation_but_not_the_child
    started = start(invoking(%(<state id="x"/>), %(<transition event="e.go" target="b"/>), %(<state id="b"/>)))
    position = moved(Statifier.export_position(started.state))
    imported = moved(Statifier.import_position(started.state.machine_state.machine, position))

    assert_equal [{ "state" => "a", "invoke_index" => 0, "invoke_id" => "c" }], position["active_invocations"]
    assert_equal [{ [1, 0] => "c" }, {}], [imported.machine_state.active_invocations, imported.invocations]
  end
end
