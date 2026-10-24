# frozen_string_literal: true

require "test_helper"
require_relative "validator_helper"

# The gating checks of ids, targets, initial references, default
# transitions, history and final states: each error's reason, detail and
# position, as the reference reports them for the same chart.
class ValidatorStatesTest < Minitest::Test
  include ValidatorHelper

  # sabotage: keep the first occurrence of an id as the duplicate (map over
  # `_first` instead of `later` in States.duplicates); the assert_equal on
  # the errors fails.
  def test_ids_are_unique_across_states_and_data_and_never_empty
    source = doc(%(<state id="a"/><state id="a"/><state id=""/><datamodel><data id="a"/></datamodel>))

    assert_equal [[:duplicate_id, { id: "a" }, 1, 88],
                  [:empty_id, {}, 1, 103],
                  [:duplicate_id, { id: "a" }, 1, 127]], errors_of(source)
  end

  # sabotage: resolve every target (`reject { true }` in States.targets);
  # the assert_equal on the unresolved ids fails.
  def test_every_transition_target_resolves
    assert_equal [[:unresolved_target, { id: "b" }, 1, 96], [:unresolved_target, { id: "c" }, 1, 96]],
                 errors_of(doc(%(<state id="a"><transition target="b c a"/></state>)))
  end

  # sabotage: let a resolved initial land anywhere (`false` for the
  # outside? test in States.initial_attribute); the assert_equal on the
  # first chart fails.
  def test_initial_references_resolve_and_land_inside_their_state
    source = doc(cat(%(<state id="a" initial="b"><state id="c"/></state><state id="b"/>),
                     %(<state id="d" initial="zz"><state id="e"/></state>)), %(#{ROOT} initial="q"))
    nameless = doc(cat(%(<state id="p"><state><initial><transition target="o"/></initial>),
                       %(<state id="i"/></state></state><state id="o"/>)))

    assert_equal [[:unresolved_initial, { id: "q" }, 1, 71],
                  [:initial_not_descendant, { id: "b", parent_id: "a" }, 1, 97],
                  [:unresolved_initial, { id: "zz" }, 1, 161]], errors_of(source)
    assert_equal [[:initial_not_descendant, { id: "o", parent_id: nil }, 1, 112]], errors_of(nameless)
  end

  # sabotage: place a target by its id rather than the tree
  # (`by_id[ancestor.id].equal?(parent)` for `parent.equal?(ancestor)` in
  # Context#inside?); the assert_equal on the shared-id chart fails.
  def test_a_target_is_placed_by_the_tree_when_two_states_share_an_id
    shared = doc(cat(%(<state id="x" initial="y"><state id="z"/></state>),
                     %(<state id="x"><state id="y"/></state>)))

    assert_equal [[:initial_not_descendant, { id: "y", parent_id: "x" }, 1, 85],
                  [:duplicate_id, { id: "x" }, 1, 122]], errors_of(shared)
  end

  # sabotage: count only a state without children as atomic (drop the kind
  # test in States.initial_state); the assert_equal on the parallel fails.
  def test_an_initial_on_a_state_with_nothing_to_enter_is_reported_alone
    source = doc(cat(%(<state id="a" initial="x"/><parallel initial="y"><state id="y"/></parallel>),
                     %(<state><initial><transition target="x"/></initial></state><state id="x"/>)))

    assert_equal [[:initial_on_atomic_state, { id: "a" }, 1, 85],
                  [:initial_on_atomic_state, { id: nil }, 1, 108],
                  [:initial_on_atomic_state, { id: nil }, 1, 144]], errors_of(source)
  end

  # sabotage: let an `<initial>` hold any number of transitions (`count =
  # []` in States.default_transition); the assert_equal on the two-
  # transition initial fails.
  def test_an_initial_element_holds_one_plain_default_transition
    two = doc(cat(%(<state id="a" initial="b"><initial><transition target="b" event="e" cond="c"/>),
                  %(<transition/></initial><state id="b"/></state>)))

    assert_equal [[:initial_attribute_and_element, { id: "a" }, 1, 88],
                  [:transition_count, { owner: initial("a"), count: 2 }, 1, 88],
                  [:transition_forbidden_attribute, { owner: initial("a"), attribute: :event }, 1, 127],
                  [:transition_forbidden_attribute, { owner: initial("a"), attribute: :cond }, 1, 136],
                  [:transition_missing_target, { owner: initial("a") }, 1, 140]], errors_of(two)
  end

  # sabotage: test an empty `event` by its list (`event:
  # !transition.event.empty?` in States.forbidden); the assert_equal on
  # the written empty event fails.
  def test_an_empty_initial_and_a_written_empty_event_are_reported
    none = doc(cat(%(<state id="a"><initial/><state id="b"/></state><state id="c"><initial>),
                   %(<transition event=""/></initial><state id="d"/></state>)))

    assert_equal [[:transition_count, { owner: initial("a"), count: 0 }, 1, 76],
                  [:transition_missing_target, { owner: initial("c") }, 1, 132],
                  [:transition_forbidden_attribute, { owner: initial("c"), attribute: :event }, 1, 151]],
                 errors_of(none)
  end

  # sabotage: accept the root as a history's parent (answer true for any
  # node that is not a state in Index.compound?); the assert_equal fails
  # on the top-level history.
  def test_a_history_sits_in_a_compound_state_with_one_default_inside_it
    source = doc(cat(%(<history id="h"/><state id="a"><history id="h2" type="sideways"><transition target="z"/>),
                     %(</history><state id="z"/></state><state id="q"><history type="deep"><transition target="z"/>),
                     %(</history><state id="r"/></state>)))

    assert_equal [[:history_bad_parent, { id: "h", parent_kind: :scxml }, 1, 62],
                  [:transition_count, { owner: history("h"), count: 0 }, 1, 62],
                  [:default_entry_not_enterable, { id: "a", child_kind: :history }, 1, 93],
                  [:history_bad_type, { raw: "sideways" }, 1, 116],
                  [:default_entry_not_enterable, { id: "q", child_kind: :history }, 1, 197],
                  [:initial_not_descendant, { id: "z", parent_id: "q" }, 1, 238]], errors_of(source)
  end

  # sabotage: test a history's targets under any parent (pass true for
  # `compound` to History.outside_parent); the assert_equal fails.
  def test_a_history_under_a_final_is_reported_once_for_its_parent
    source = doc(%(<final id="f"><history id="h"><transition target="f"/></history></final>))

    assert_equal [[:history_bad_parent, { id: "h", parent_kind: :final }, 1, 76],
                  [:final_has_states, { id: "h" }, 1, 76]], errors_of(source)
  end

  # sabotage: test only a history's first transition (`state.transitions.
  # first(1)` in History.outside_parent); the assert_equal fails.
  def test_each_default_transition_of_a_history_is_read
    source = doc(cat(%(<state id="w"><history id="h3"/><history id="h4"><transition target="w"/>),
                     %(<transition target="w" cond="x"/></history></state>)))
    outside = { id: "w", parent_id: "w" }

    assert_equal [[:transition_count, { owner: history("h3"), count: 0 }, 1, 76],
                  [:default_entry_not_enterable, { id: "w", child_kind: :history }, 1, 76],
                  [:transition_count, { owner: history("h4"), count: 2 }, 1, 94],
                  [:initial_not_descendant, outside, 1, 131], [:initial_not_descendant, outside, 1, 155],
                  [:transition_forbidden_attribute, { owner: history("h4"), attribute: :cond }, 1, 164]],
                 errors_of(source)
  end

  # sabotage: name a final's transition by the transition's own id (id:
  # nil for :final_has_transitions in History.finals); the assert_equal
  # fails.
  def test_a_final_holds_no_state_and_no_transition
    assert_equal [[:final_has_states, { id: "g" }, 1, 76], [:final_has_transitions, { id: "f" }, 1, 91]],
                 errors_of(doc(%(<final id="f"><state id="g"/><transition target="f"/></final>)))
  end

  # sabotage: name the last final rather than the first (`reverse.find` in
  # History.final_parents); the assert_equal on the two-final parent fails.
  def test_the_parent_of_a_final_has_an_id
    source = doc(cat(%(<state><final id="f1"/><final id="f2"/></state><parallel><final/></parallel>),
                     %(<state id="ok"><final/></state>)))

    assert_equal [[:final_parent_missing_id, { final_id: "f1" }, 1, 62],
                  [:final_parent_missing_id, { final_id: nil }, 1, 109]], errors_of(source)
  end

  # sabotage: read a parallel's first child too (drop `state.kind ==
  # :state` in History.default_entries); the assert_equal fails on the
  # parallel.
  def test_a_state_entered_by_default_does_not_start_at_a_history
    source = doc(cat(%(<state id="a"><history id="h"><transition target="b"/></history><state id="b"/></state>),
                     %(<parallel id="p"><history id="h2"><transition target="c"/></history><state id="c"/></parallel>)))

    assert_equal [[:default_entry_not_enterable, { id: "a", child_kind: :history }, 1, 76]], errors_of(source)
  end
end
