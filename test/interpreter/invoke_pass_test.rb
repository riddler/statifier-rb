# frozen_string_literal: true

require "test_helper"
require_relative "invoke_helper"

# The interpreter's invoke pass: starting a state's invocations at the end
# of a macrostep.
class InvokePassTest < Minitest::Test
  include LoopInvokeHelper

  ARGUMENTS = <<~XML
    <datamodel><data id="x" expr="5"/></datamodel>
    <state id="a">
      <invoke typeexpr="'scxml'" srcexpr="'file:c.scxml'" autoforward="true"><param name="p" expr="x + 1"/></invoke>
    </state>
  XML

  IDLOCATION = <<~XML.freeze
    <datamodel><data id="where"/></datamodel>
    <state id="a">
      <invoke idlocation="where">#{CHILD}</invoke>
      <invoke id="b"><param name="p" expr="where"/></invoke>
    </state>
  XML

  FAILING = <<~XML.freeze
    <state id="a">
      <invoke id="bad"><param name="p" expr="nope"/></invoke>
      <invoke id="good">#{CHILD}</invoke>
    </state>
  XML

  # sabotage: answer `"inv_#{counter}"` whatever the owner's id in
  # Invoke.mint; the assert_equal on the invoke ids fails.
  def test_the_pass_answers_an_invoke_effect_with_a_generated_id_after_the_state_s_id
    started = start(%(<state id="a"><invoke>#{CHILD}</invoke><invoke id="mine">#{CHILD}</invoke></state>))

    assert_equal %w[a.inv_1 mine], started.effects.grep(E::Invoke).map(&:invoke_id)
    assert_equal 1, started.state.invoke_counter
    assert_equal({ [1, 0] => "a.inv_1", [1, 1] => "mine" }, started.state.active_invocations)
  end

  # sabotage: answer `params: Predicator::UNDEFINED` in Arguments.rest; the
  # assert_equal on the fields fails.
  def test_the_invoke_effect_carries_the_resolved_arguments
    invoke = start(ARGUMENTS).effects.grep(E::Invoke).first

    assert_equal ["scxml", "file:c.scxml", { "p" => 6 }, nil, true, 1, 0],
                 invoke.to_h.values_at(:type, :src, :params, :content, :autoforward, :state_index, :invoke_index)
  end

  # sabotage: record every type live in Invoke.started (drop the
  # `if built_in_type?` guard); the assert_equal on the live invocations
  # fails.
  def test_an_invocation_of_another_type_is_answered_and_not_recorded_live
    started = start(%(<state id="a"><invoke id="x" type="other"/><invoke id="y" type="scxml"/></state>), trace: true)

    assert_equal %w[x y], started.effects.grep(E::Invoke).map(&:invoke_id)
    assert_equal({ [1, 1] => "y" }, started.state.active_invocations)
    assert_equal [%w[y]], started.effects.grep(T::InvokePass).map(&:invoke_ids).reject(&:empty?)
  end

  # sabotage: answer `effects + [effect(...)] + changes(...)` in
  # Invoke.started; the assert_equal on the effect kinds fails.
  def test_idlocation_is_written_before_the_invoke_effect_and_read_by_the_next_invocation
    effects = start(IDLOCATION).effects
    change = effects.grep(E::DatamodelChange).last

    assert_equal %w[DatamodelChange DatamodelChange Invoke Invoke], kinds(effects).grep(/\A(DatamodelChange|Invoke)\z/)
    assert_equal [["where"], "a.inv_1", { kind: :invoke, state_index: 1, invoke_index: 0 }, nil],
                 change.to_h.values_at(:location_path, :new_value, :owner, :c_index)
    assert_equal({ "p" => "a.inv_1" }, effects.grep(E::Invoke).last.params)
  end

  # sabotage: answer `[state, context, effects]` without the raise in
  # Invoke.invoke_one; the assert_equal on the dequeued events fails.
  def test_an_argument_that_fails_raises_error_execution_and_its_sibling_still_starts
    started = start(FAILING, trace: true)
    failures = dequeued(started.effects).map { [_1[0], _1[4]] }

    assert_equal %w[good], started.effects.grep(E::Invoke).map(&:invoke_id)
    assert_equal [["error.execution", { kind: :invoke, state_index: 1, invoke_index: 0 }]], failures
  end
end
