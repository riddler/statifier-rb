# frozen_string_literal: true

require "test_helper"

# Statifier.check_accepts: a declaration of the event names a chart
# accepts against the chart's event vocabulary, as the reference's
# `Statifier.Chart.check_accepts/2` answers it.
class CheckAcceptsTest < Minitest::Test
  ROOT = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  def machine(body, initial = nil)
    attribute = initial ? %( initial="#{initial}") : ""
    compiled = Statifier.compile(%(<scxml #{ROOT}#{attribute}>#{body}</scxml>))
    assert_predicate compiled, :ok?, compiled.error.inspect
    compiled.value
  end

  def check(body, declared, initial = nil) = Statifier.check_accepts(machine(body, initial), declared)

  # One state listening for `descriptor`, and a state it targets.
  def listening(descriptor) = %(<state id="a"><transition event="#{descriptor}" target="b"/></state><state id="b"/>)

  # sabotage: drop `.sort` in Accepts.vocabulary; the assert_equal on the
  # order fails (descriptors then follow the walk's order, which enters q
  # first).
  def test_undeclared_descriptors_come_in_transition_order_own_before_children_and_each_once
    body = <<~XML
      <state id="p" initial="a">
        <state id="a"><transition event="e.a1 e.a2" target="b"/></state>
        <state id="b"><transition event="e.b e.a1" target="a"/></state>
        <transition event="e.p" target="q"/>
      </state>
      <state id="q"><transition event="e.q" target="p"/></state>
    XML

    assert_equal %w[e.p e.a1 e.a2 e.b e.q], check(body, [], "q").undeclared
  end

  # sabotage: match a declared name by exact token equality in
  # Accepts.unreachable (`descriptor_tokens.include?(_2)` for the matcher);
  # the assert_equal on the matched descriptors fails.
  def test_a_declared_name_is_matched_on_token_boundaries_by_prefixes_and_wildcards
    matched = %w[e.go e.* e. e *].select { check(listening(_1), ["e.go"]).unreachable.empty? }
    unmatched = %w[e.gone e.go.now f].select { check(listening(_1), ["e.go"]).unreachable == ["e.go"] }

    assert_equal %w[e.go e.* e. e *], matched
    assert_equal %w[e.gone e.go.now f], unmatched
  end

  # sabotage: swap the matcher's arguments in Accepts.unreachable
  # (`name_match?([_2], ...)` over each descriptor's tokens); the
  # assert_equal on the descriptor `e.go` fails (the declared `e.*` is
  # then read as a pattern).
  def test_a_star_in_a_declared_name_is_an_ordinary_token
    assert_equal [], check(listening("e"), ["e.*"]).unreachable
    assert_equal ["e.*"], check(listening("e.go"), ["e.*"]).unreachable
    assert_equal [], check(listening("e.*"), ["e.*"]).unreachable
  end

  # A chart whose states are entered only by each part of the rule: an
  # ancestor's transition (`e.p`), a parallel's untargeted region (`e.y`), a
  # history's default target (`e.c2`); and a state no path enters (`e.z`).
  REACH = <<~XML
    <state id="a">
      <transition event="e.a" target="x2"/>
      <transition event="e.h" target="h"/>
    </state>
    <parallel id="p">
      <transition event="e.p" target="a"/>
      <state id="x" initial="x1"><state id="x1"/><state id="x2"><transition event="e.x2" target="a"/></state></state>
      <state id="y"><transition event="e.y" target="a"/></state>
    </parallel>
    <state id="c" initial="c1">
      <history id="h"><transition target="c2"/></history>
      <state id="c1"><transition event="e.c1" target="a"/></state>
      <state id="c2"><transition event="e.c2" target="a"/></state>
    </state>
    <state id="z"><transition event="e.z" target="a"/></state>
  XML

  # sabotage: answer [] from Accepts.untargeted_regions; the assert_equal
  # fails (`e.y` is left out).
  # sabotage: answer [] for a history in Accepts.default_entry; the
  # assert_equal fails (`e.c2` is left out).
  # sabotage: answer every state index from Accepts.entered_states; the
  # assert_equal fails (`e.z` and `e.c1` join).
  def test_the_vocabulary_holds_exactly_the_descriptors_of_states_some_path_enters
    assert_equal %w[e.a e.h e.p e.x2 e.y e.c2], check(REACH, [], "a").undeclared
  end

  # sabotage: drop `.uniq` on the declared names in Accepts.check; the first
  # assert_equal fails (the name is answered twice).
  def test_unreachable_names_keep_the_declaration_order_without_duplicates
    assert_equal %w[e.z e.y], check(listening("e.go"), %w[e.z e.go e.y e.z]).unreachable
    assert_equal [], check(listening("e.go"), %w[e.z e.go]).undeclared
  end

  # sabotage: answer the whole vocabulary as `undeclared` for nil in
  # Accepts.check; the first assert_equal fails.
  def test_no_declaration_answers_two_empty_lists_and_an_empty_one_the_whole_vocabulary
    assert_equal [[], []], check(listening("e.go"), nil).to_h.values
    assert_equal [[], ["e.go"]], check(listening("e.go"), []).to_h.values
  end

  # sabotage: freeze each declared name in place in Accepts.check
  # (`map(&:freeze)` for `map(&:-@)`); the refute_predicate on the host's
  # name fails.
  def test_the_answer_is_deeply_frozen_and_the_declared_names_are_never_frozen
    name = +"e.stop"
    answer = check(listening("e.go"), [name])

    refute_predicate name, :frozen?
    assert_equal ["e.stop"], answer.unreachable
    assert Ractor.shareable?(answer)
  end

  # sabotage: drop the declared-name check in Statifier.check_accepts; the
  # last assert_raises fails (a NoMethodError is raised instead).
  def test_a_machine_a_declaration_or_a_name_of_the_wrong_kind_raises
    chart = machine(listening("e.go"))

    assert_raises(TypeError) { Statifier.check_accepts("<scxml/>", []) }
    assert_raises(TypeError) { Statifier.check_accepts(chart, "e.go") }
    assert_raises(TypeError) { Statifier.check_accepts(chart, [:e]) }
  end
end
