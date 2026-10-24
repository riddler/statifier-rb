# frozen_string_literal: true

require "test_helper"
require_relative "content_helper"

# send and cancel: the effects, the send ids, the payload, the argument
# failures that discard a send, and the refusals that keep its id.
class SendTest < Minitest::Test
  include ContentHelper

  S = Statifier::Interpreter::Send
  T = Statifier::Interpreter::Targets
  FIELDS = { owner: OWNER, macrostep: 2, microstep: 3, round: 4 }.freeze

  def sends(**fields) = S::SendState::INITIAL.with(**fields)

  def routes(sessions: [], parent: false, invokes: []) = T::Routes.new(sessions:, parent?: parent, invokes:)

  # sabotage: build Effect::Send with target: nil in Send.send_effect; the
  # assert_equal on the effect fails.
  def test_an_immediate_send_answers_one_send_effect_whatever_its_target
    outcome = run_block(%(<send event="go" target="#_internal"/>))

    assert_equal [E::Send.new(event: "go", target: "#_internal", type: nil, data: Predicator::UNDEFINED,
                              send_id: "send_1", c_index: 0, ordinal: nil, id_from_author?: false, **FIELDS)],
                 outcome.effects
    assert_empty outcome.raised
  end

  # sabotage: drop `sends = sends.tick if stamps` in Send.accepted; the
  # assert_equal on the ordinals fails.
  def test_a_delayed_send_answers_its_delay_and_an_ordinal
    outcome = run_block(%(<send event="a" delay="1.5s"/><send event="b" delayexpr="'.5s'" id="t"/>))

    assert_equal([[1500, 1, "send_1", false], [500, 2, "t", true]],
                 outcome.effects.map { [_1.delay_ms, _1.ordinal, _1.send_id, _1.id_from_author?] })
    assert_equal [1, 2], outcome.sends.to_h.values_at(:send_counter, :timer_counter)
  end

  # sabotage: answer [node.id, sends.mint] for an author id in Send.mint;
  # the assert_equal on the ids fails.
  def test_generated_send_ids_count_and_an_author_id_consumes_none
    outcome = run_block(%(<send event="a"/><send event="b" id="mine"/><send event="c"/>))

    assert_equal %w[send_1 mine send_2], outcome.effects.map(&:send_id)
    assert_equal 2, outcome.sends.send_counter
  end

  # sabotage: put the change after the effect ((changes << effect) to
  # [effect, *changes]) in Send.accepted; the assert_equal on the classes
  # fails.
  def test_an_idlocation_is_written_before_the_send_and_answers_its_change
    outcome = run_block(%(<send event="a" idlocation="s"/><log expr="s"/>))
    change, send, log = outcome.effects

    assert_equal [E::DatamodelChange, E::Send, E::Log], outcome.effects.map(&:class)
    assert_equal [["s"], "send_1", "hello", true], [change.location_path, change.new_value, change.prior_value,
                                                    send.id_from_author?]
    assert_equal "send_1", log.value
  end

  # sabotage: answer pairs.reverse.to_h in Send.params_data; the
  # assert_equal on the data fails, as the first p wins.
  def test_namelist_and_params_become_the_data_the_last_repeated_name_winning
    outcome = run_block(<<~XML)
      <send event="a" namelist="x s"/>
      <send event="b"><param name="p" expr="x + 1"/><param name="q" location="l"/><param name="p" expr="'again'"/></send>
    XML

    assert_equal [{ "x" => 1, "s" => "hello" }, { "p" => "again", "q" => [1, 2, 3] }], outcome.effects.map(&:data)
  end

  # sabotage: take `text.to_s` untrimmed as `trimmed` in Send.text_data;
  # the assert_equal on the data fails.
  def test_content_text_reads_as_a_literal_or_space_normalized_text
    outcome = run_block(<<~XML)
      <send event="a"><content>[1, 2]</content></send><send event="b"><content>  some   words
        here </content></send><send event="c"><content>   </content></send><send event="d"><content expr="m"/></send>
    XML

    assert_equal [[1, 2], "some words here", Predicator::UNDEFINED, { "a" => 1 }], outcome.effects.map(&:data)
  end

  # sabotage: answer resolved.merge(...) whether or not data.ok? in
  # Send.resolve_rest; the assert_empty on the effects fails.
  def test_an_argument_that_fails_discards_the_send_and_mints_nothing
    outcome = run_block(%(<send event="a" id="keep"><param name="p" expr="nope"/></send><raise event="never"/>))

    assert_empty outcome.effects
    assert_equal ["error.execution"], raised_names(outcome)
    assert_equal "evaluator_error", outcome.raised.first.data["kind"]
  end

  # sabotage: answer Datamodel.evaluate(context, delay) without the
  # milliseconds in Send.resolve_delay; the assert_equal on the reason fails.
  def test_a_delay_that_is_not_a_duration_discards_the_send
    outcome = run_block(%(<send event="a" delayexpr="5" idlocation="s"/>))

    assert_equal [rv(DM::InvalidDelay.new(value: 5))], reasons(outcome)
    assert_equal ["hello", 0], [outcome.context.data["s"], outcome.sends.send_counter]
  end

  # sabotage: pass `context` in place of `write ? write.context : context`
  # to Send.judged in Send.execute_send; the last assert_equal fails, as
  # the refused send's idlocation write is lost.
  def test_an_invalid_target_is_refused_keeping_its_id_and_its_idlocation_write
    outcome = run_block(%(<send event="a" target="nowhere" idlocation="s"/><raise event="never"/>))
    error = outcome.raised.last

    assert_empty outcome.effects
    assert_equal ["error.execution", origin(0), rv(T::InvalidTarget.new(target: "nowhere")), "send_1"],
                 [error.name, *origin_and_data(error), error.sendid]
    assert_equal "send_1", outcome.context.data["s"]
  end

  # sabotage: answer :built_in for every type in Targets.classify; the
  # assert_equal on the reason fails.
  def test_an_unsupported_type_is_refused_as_error_execution
    outcome = run_block(%(<send event="a" type="x-custom"/>))

    assert_equal([["error.execution", rv(T::UnsupportedType.new(type: "x-custom"))]],
                 outcome.raised.map { [_1.name, _1.data] })
  end

  # sabotage: answer `"error.execution"` for every kind in
  # Content.error_event; the assert_equal on the name fails.
  def test_an_unreachable_target_is_refused_as_error_communication
    outcome = run_block(%(<send event="a" target="#_scxml_other"/><send event="b" target="#_scxml_gone"/>),
                        sends(routes: routes(sessions: ["other"])))

    assert_equal ["send_1"], outcome.effects.map(&:send_id)
    assert_equal([["error.communication", rv(T::UnreachableTarget.new(target: "#_scxml_gone")), "send_2"]],
                 outcome.raised.map { [_1.name, _1.data, _1.sendid] })
  end

  # sabotage: drop `!delay_ms.nil? ||` from Targets.target_reason; the
  # assert_equal on the classes fails, as the delayed send is refused.
  def test_a_delayed_send_s_route_is_not_judged_and_no_routes_judges_nothing
    declared = run_block(%(<send event="a" target="#_parent" delay="1s"/>), sends(routes: routes))
    undeclared = run_block(%(<send event="a" target="#_parent"/>))

    assert_equal([[E::SendDelayed], [E::Send]], [declared, undeclared].map { _1.effects.map(&:class) })
  end

  # sabotage: answer `target_reason(...)` for :registered in
  # Targets.reject_reason; the assert_equal on the ordinals fails, as the
  # target is refused.
  def test_a_registered_type_carries_its_target_unparsed_and_an_ordinal
    outcome = run_block(%(<send event="a" type="x-custom" target="any route"/><send event="b"/>),
                        sends(send_types: ["x-custom"], routes: routes))

    assert_equal([["any route", 1], [nil, nil]], outcome.effects.map { [_1.target, _1.ordinal] })
  end
end
