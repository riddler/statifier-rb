# frozen_string_literal: true

require_relative "position_helper"

# Position export: the position's keys and values, what is left out of it,
# and each refusal.
class PositionExportTest < Minitest::Test
  include PositionHelper

  # sabotage: export the status as "done" in Position.flags; the
  # assert_equal on the position fails.
  def test_export_answers_the_position_in_the_string_id_vocabulary
    state = after("e.go", "e.out")
    exported = position(state)

    assert_equal Statifier::Position::KEYS, exported.keys
    assert_equal({ "configuration" => %w[b], "entered_states" => %w[a a1 a2 b], "states_to_invoke" => [],
                   "history_values" => { "h" => %w[a2] }, "active_invocations" => [], "invoke_counter" => 0,
                   "send_counter" => 0, "timer_counter" => 0, "running" => true, "status" => "running",
                   "macrostep" => 3, "microstep" => 1, "round" => 1, "trace" => false,
                   "max_macrostep_rounds" => 10_000 }, exported.except("datamodel"))
    assert_equal({ "_name" => '{"$type":"undefined"}', "_sessionid" => '"s1"', "n" => "1" },
                 exported["datamodel"].slice("_name", "_sessionid", "n"))
  end

  # sabotage: drop the Ractor.make_shareable in Position.exported; the
  # assert_predicate on the frozen position fails.
  def test_export_answers_plain_frozen_data_that_survives_json_and_leaves_the_state_as_it_was
    state = after("e.go")
    exported = position(state)

    assert_equal exported, through_json(exported)
    assert Ractor.shareable?(exported)
    assert_equal %w[a a2], active(Statifier::Driver::Moved.new(state:, effects: []))
  end

  # sabotage: copy the pending timers into the position in
  # Position.exported; the assert_equal on the keys fails.
  def test_export_writes_no_member_of_the_driver
    state = start(%(<state id="a"><onentry><send event="t" delay="5s"/></onentry></state>)).state

    assert_equal 1, state.timers.size
    assert_equal Statifier::Position::KEYS, position(state).keys
  end

  # sabotage: drop the internal-queue check in Position.export; the
  # refute_predicate in `refusal` fails (the export succeeds).
  def test_export_refuses_a_state_whose_internal_queue_holds_an_event
    looping = %(<state id="a"><onentry><raise event="r"/></onentry><transition event="r" target="a"/></state>)
    halted = start(looping, max_macrostep_rounds: 2).state

    assert_equal [:internal_queue_not_empty, {}], refusal(Statifier.export_position(halted))
  end

  # sabotage: keep the root among the unnameable indexes (drop `_1.zero? ||`
  # in Position.unnameable); the assert_equal on the indexes fails.
  def test_export_refuses_a_state_with_no_id_naming_every_index
    unnamed = start(%(<parallel id="p"><state/><state><state id="c"/></state></parallel>)).state

    assert_equal [:unnameable_states, { indexes: [2, 3] }], refusal(Statifier.export_position(unnamed))
  end

  # sabotage: drop the refusal line in Text.encode (keep a value the codec
  # refused as nil); the refute_predicate in `refusal` fails (the export
  # succeeds).
  def test_export_refuses_a_value_the_tagged_encoding_has_no_form_for
    state = start(%(<state id="a"/>), datamodel: { "v" => :sym }).state

    assert_equal [:unencodable_value, { field: "datamodel.v", reason: "unsupported_value" }],
                 refusal(Statifier.export_position(state))
  end

  # sabotage: call Position.export without Driver::Checks.state in
  # Statifier.export_position; the assert_raises fails (NoMethodError).
  def test_export_takes_only_a_driver_state
    assert_raises(TypeError) { Statifier.export_position({}) }
  end
end
