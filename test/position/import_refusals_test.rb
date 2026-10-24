# frozen_string_literal: true

require_relative "position_helper"

# Position import's refusals: a value that is not a position, each field
# of the wrong shape, a datamodel that does not decode, and ids the chart
# does not hold.
class PositionImportRefusalsTest < Minitest::Test
  include PositionHelper

  # sabotage: drop `.sort` on the missing keys in Shape.failure; the
  # assert_equal on the keys fails.
  def test_an_import_refuses_a_position_that_is_not_one_as_malformed
    exported = through_json(position(after))
    import = ->(value) { refusal(Statifier.import_position(machine(CHART), value)) }

    assert_equal [:malformed_export, { kind: :not_a_hash }], import.call([])
    assert_equal [:malformed_export, { kind: :missing_keys, keys: %w[datamodel history_values] }],
                 import.call(exported.except("history_values", "datamodel"))
    assert_equal [:malformed_export, { kind: :missing_keys, keys: Statifier::Position::KEYS.sort }],
                 import.call(exported.transform_keys(&:to_sym))
  end

  # sabotage: accept any `running` value in Shape::CHECKS; the
  # refute_predicate in `refusal` fails on the `running` import.
  def test_an_import_refuses_the_first_field_of_the_wrong_shape_naming_it
    exported = through_json(position(after))
    import = ->(changes) { refusal(Statifier.import_position(machine(CHART), exported.merge(changes))) }

    assert_equal [:malformed_export, { kind: :bad_shape, field: "configuration" }],
                 import.call("configuration" => [1], "running" => "yes")
    assert_equal [:malformed_export, { kind: :bad_shape, field: "running" }], import.call("running" => "yes")
  end

  # sabotage: accept a round budget of 0 (`value >= 0` in Shape::CHECKS);
  # the refute_predicate in `refusal` fails (the import succeeds).
  def test_an_import_takes_a_positive_round_budget_or_infinity
    exported = through_json(position(after))
    import = ->(budget) { Statifier.import_position(machine(CHART), exported.merge("max_macrostep_rounds" => budget)) }

    assert_equal [:malformed_export, { kind: :bad_shape, field: "max_macrostep_rounds" }], refusal(import.call(0))
    assert_equal :infinity, import.call("infinity").value.machine_state.max_macrostep_rounds
  end

  # sabotage: drop the undecodable-value refusal line in Text.decode; the
  # refute_predicate in `refusal` fails on the undecodable text.
  def test_an_import_refuses_a_datamodel_text_that_does_not_decode_or_no_session_id
    exported = through_json(position(after))
    import = lambda { |datamodel|
      refusal(Statifier.import_position(machine(CHART), exported.merge("datamodel" => datamodel)))
    }

    assert_equal [:malformed_export, { kind: :undecodable_value, field: "datamodel.n" }],
                 import.call(exported["datamodel"].merge("n" => "{"))
    assert_equal [:malformed_export, { kind: :no_session_id, field: "datamodel._sessionid" }],
                 import.call(exported["datamodel"].merge("_sessionid" => "1"))
  end

  # sabotage: answer only the first unknown id (`.first(1)` in
  # Shape.unknown_ids); the assert_equal on the ids fails.
  def test_an_import_refuses_every_id_the_chart_does_not_hold_after_the_shape_checks
    exported = through_json(position(after("e.go", "e.out")))
    other = machine(%(<state id="b"><state id="x"/></state>))

    assert_equal [:unknown_state_ids, { ids: %w[a a1 a2 h] }], refusal(Statifier.import_position(other, exported))
    assert_equal :malformed_export, refusal(Statifier.import_position(other, exported.merge("trace" => 1))).first
  end

  # sabotage: drop the machine check in Statifier.import_position; the
  # assert_raises fails (the import answers a refusal).
  def test_an_import_takes_only_a_machine
    assert_raises(TypeError) { Statifier.import_position(nil, {}) }
  end
end
