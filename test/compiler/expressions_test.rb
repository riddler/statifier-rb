# frozen_string_literal: true

require "test_helper"
require_relative "compiler_helper"

# Every expression compiles through predicator: conditions and values
# through Predicator.compile, script bodies through
# Predicator.compile_program; a refusal is a load-time error or deferred,
# class by class, as the reference has it.
class CompilerExpressionsTest < Minitest::Test
  include CompilerHelper

  # sabotage: compile a condition as a program (Predicator.compile_program in
  # Expressions.compile); the assert_equal on the instructions fails.
  def test_a_condition_compiles_through_predicator_compile
    body = '<state id="a"><transition cond="x > 1" target="a"/></state>'
    transition = machine(body).transitions.first

    assert_equal Predicator.compile!("x > 1"), transition.cond.instructions
    assert_equal "x > 1", transition.cond.source
    assert_equal "x > 1", transition.cond_location.slice(doc(body))
  end

  # sabotage: compile a script as an expression (Predicator.compile in
  # Expressions.program); the assert_instance_of fails.
  def test_a_script_compiles_through_predicator_compile_program
    script = content_of("<script>x = 1; y = x + 1</script>").first

    assert_instance_of Internals::Machine::Program, script.program
    assert_equal Predicator.compile_program!("x = 1; y = x + 1"), script.program.instructions
  end

  # sabotage: drop the global scripts (map over an empty list in
  # Compiler.global_scripts); the assert_equal fails.
  def test_a_top_level_script_compiles_as_a_program
    m = machine('<script>x = 1</script><state id="a"/>')

    assert_equal [Predicator.compile_program!("x = 1")], m.global_scripts.map(&:instructions)
  end

  # sabotage: answer a script's refusal unwrapped (drop the Invalid in
  # Expressions.program); the assert_instance_of fails.
  def test_a_script_body_that_does_not_compile_is_deferred
    script = content_of("<script>x = </script>").first

    assert_instance_of Internals::Machine::Invalid, script.program
    assert_equal [:expression_compile_error, { kind: :content, c_index: 0 }],
                 [script.program.error.reason, script.program.error.detail[:owner]]
  end

  # sabotage: answer a deferred refusal as it is (deferred returns its
  # argument in Expressions.deferred); the first assert_instance_of fails.
  def test_assign_and_namelist_refusals_are_deferred
    assign, send = content_of('<assign location="x" expr="2 +"/><send event="e" namelist="x("/>')

    assert_instance_of Internals::Machine::Invalid, assign.value
    assert_instance_of Internals::Machine::Invalid, send.namelist.first.expr
  end

  # sabotage: answer a data refusal unwrapped (drop Expressions.deferred in
  # Parts#data_value); the assert_instance_of fails.
  def test_a_data_refusal_is_deferred
    data = machine('<datamodel><data id="x" expr="1 +"/></datamodel>').data_elements.first

    assert_instance_of Internals::Machine::Invalid, data.value
    assert_equal({ kind: :data, d_index: 0 }, data.value.error.detail[:owner])
  end

  # sabotage: compile a literal attribute instead of folding it
  # (Expressions.compile for the literal in Parts#pair); the assert_equal on
  # the event fails.
  def test_send_and_cancel_fold_literals_and_compile_their_twins
    send, cancel = content_of('<send event="e.go" targetexpr="t" delay="1s"/><cancel sendid="s1"/>')

    assert_equal Internals::Machine::Static.new(value: "e.go"), send.event
    assert_equal Predicator.compile!("t"), send.target.instructions
    assert_equal Internals::Machine::Static.new(value: "1s"), send.delay
    assert_nil send.type
    assert_equal Internals::Machine::Static.new(value: "s1"), cancel.sendid
  end

  # sabotage: fold every body to its trimmed text (static(trimmed) in
  # Expressions.inline_value); the first assert_equal fails.
  def test_inline_values_fold_to_literals_or_to_their_text
    m = machine('<datamodel><data id="a"> [1, 2] </data><data id="b">x</data><data id="c"/>' \
                '<data id="d" src="file:d"/><data id="e"> x  y </data></datamodel>')

    assert_equal([[1, 2], "x", nil, "x  y"], m.data_elements.values_at(0, 1, 2, 4).map { _1.value.value })
    assert_equal Internals::Machine::Src.new(src: "file:d"), m.data_elements[3].value
  end

  # sabotage: drop the markup rung (no markup return in Parts#text_value); the
  # assert_equal fails.
  def test_an_assign_with_markup_holds_the_markup_as_a_string
    assign = content_of('<assign location="x"><b/></assign>').first

    assert_equal "<b/>", assign.value.value
  end

  # sabotage: drop the transitions' group from the merge (values.drop(1) in
  # Compiler.compile); the assert_equal fails.
  def test_each_load_time_class_is_refused_in_document_order
    body = '<state id="a"><onentry><log expr="1 +"/><if cond="("><elseif cond=")"/></if>' \
           '<foreach array="[" item="i"/><cancel sendidexpr="!"/></onentry>' \
           '<transition cond="x ==" target="a"/></state>'

    expected = [[0, "log", "expr", "1 +"], [1, "if", "cond", "("], [1, "elseif", "cond", ")"],
                [2, "foreach", "array", "["], [3, "cancel", "sendidexpr", "!"]].map do |c_index, *site, source|
      row({ kind: :content, c_index: }, *site, source, column_of(body, %("#{source}")) + 1)
    end

    assert_equal expected + [row({ kind: :transition, t_index: 0 }, "transition", "cond", "x ==",
                                 column_of(body, "x =="))], refusals(body)
  end

  # sabotage: keep compiling a <send> after its first refusal (drop the early
  # return in Content#send_values); the first assert_equal fails.
  def test_a_send_answers_its_first_refusal_and_its_params_only_when_the_rest_compiled
    first = '<state id="a"><onentry><send eventexpr="(" targetexpr=")"><param name="p" expr="]"/></send>' \
            "</onentry></state>"
    params = '<state id="a"><onentry><send event="e"><param name="p" expr="("/><param name="q" expr=")"/>' \
             "</send></onentry></state>"

    assert_equal([%w[send eventexpr (]], refusals(first).map { _1[2, 3] })
    assert_equal([%w[param expr (], %w[param expr )]], refusals(params).map { _1[2, 3] })
  end

  # sabotage: drop the donedata params' refusals (keep only the Params in
  # Parts#build_donedata); the assert_equal fails.
  def test_donedata_and_invoke_expressions_are_load_time_errors
    body = '<state id="a"><invoke typeexpr="(" srcexpr=")"><param name="p" location="]"/></invoke>' \
           '<invoke><content expr="["/></invoke></state><final id="f"><donedata><param name="d" expr="!"/>' \
           "</donedata></final>"
    invoke = { kind: :invoke, state_index: 1, invoke_index: 0 }
    second = { kind: :invoke, state_index: 1, invoke_index: 1 }

    assert_equal([[invoke, "invoke", "typeexpr"], [invoke, "invoke", "srcexpr"], [invoke, "param", "location"],
                  [second, "content", "expr"], [{ kind: :donedata, state_index: 2 }, "param", "expr"]],
                 refusals(body).map { _1[1, 3] })
  end

  # sabotage: drop predicator's position from the message (no "(predicator
  # line" part in Expressions.refusal); the assert_equal on the message fails.
  def test_a_refusal_carries_predicators_error_and_the_references_message
    error = Statifier.compile(doc('<state id="a"><transition cond="x &quot;y" target="a"/></state>')).error.first

    assert_instance_of Predicator::ParseError, error.detail[:error]
    assert_equal "failed to compile expression \"x \\\"y\": #{error.detail[:error].message} " \
                 "(predicator line 1, column 3)", error.message
  end
end
