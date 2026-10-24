# frozen_string_literal: true

require "test_helper"
require_relative "datamodel_helper"

# Datamodel::DataBinding: every <data> created, bound early or late, the
# host's root values kept, and a value that fails raising error.execution.
class DataBindingTest < Minitest::Test
  include DatamodelHelper

  B = D::DataBinding

  CHART = <<~SCXML
    <datamodel><data id="a" expr="1"/><data id="b">[1, 2]</data><data id="c" expr="1 +"/>
    <data id="d" src="v.json"/><data id="f" expr="nope"/></datamodel>
    <state id="s1"><datamodel><data id="e" expr="2"/></datamodel></state><state id="s2"/>
  SCXML

  def chart(binding) = machine(CHART, %(#{ROOT} binding="#{binding}"))

  # A raised reason as a row: a compile refusal's reason, an evaluation
  # failure's source, any other reason itself.
  def reason_row(reason)
    case reason
    when Internals::Compiler::Error then reason.reason
    when D::EvaluatorError then reason.source
    else reason
    end
  end

  # sabotage: bind the root's own <data> only (indexes = root_data) under
  # early binding in DataBinding.start; the assert_equal on e fails.
  def test_early_binding_binds_every_data_when_the_chart_starts
    bound = B.start(context(machine: chart("early")))

    assert_equal({ "a" => 1, "b" => [1, 2], "c" => U, "d" => U, "e" => 2, "f" => U }, authored(bound.data))
  end

  # sabotage: carry no src (SrcValue.new(src: nil)) in DataBinding.value_of;
  # the assert_equal on the rows fails.
  def test_a_value_that_fails_is_a_failure_and_leaves_the_id_undefined
    failures = B.start(context(machine: chart("early"))).failures

    rows = failures.map { [_1.d_index, reason_row(_1.reason)] }

    assert_equal [[2, :expression_compile_error], [3, D::SrcValue.new(src: "v.json")], [4, "nope"]], rows
  end

  # sabotage: bind every index under late binding too (drop the binding test
  # in DataBinding.start); the assert_same on e fails.
  def test_late_binding_binds_only_the_roots_own_when_the_chart_starts
    bound = B.start(context(machine: chart("late")))

    assert_equal 1, bound.data["a"]
    assert_same U, bound.data["e"]
  end

  # sabotage: drop the host_ids reject in DataBinding.start; the assert_equal
  # on a fails (1).
  def test_a_root_data_the_host_supplied_keeps_the_hosts_value
    assert_equal "host", B.start(context({ "a" => "host" }, machine: chart("early"))).data["a"]
  end

  # sabotage: answer the empty Bound for every state (return ... if true) in
  # DataBinding.enter_state; the assert_equal on 2 fails.
  def test_late_binding_binds_a_states_own_data_on_entry
    started = B.start(context(machine: chart("late")))
    entered = B.enter_state(D.context(started.data, chart("late"), [1]), 1)

    assert_equal [2, []], [entered.data["e"], entered.failures]
  end

  # sabotage: record no failure (answer [data, changes, failures]) in
  # DataBinding.bind_one; the assert_equal on the failures fails.
  def test_a_states_own_data_that_fails_on_entry_is_a_failure
    failing = machine('<state id="s1"><datamodel><data id="e" expr="nope"/></datamodel></state>',
                      %(#{ROOT} binding="late"))
    entered = B.enter_state(B.start(context(machine: failing)).then { D.context(_1.data, failing, [1]) }, 1)

    assert_equal([[0, "nope"]], entered.failures.map { [_1.d_index, _1.reason.source] })
    assert_same U, entered.data["e"]
  end

  # sabotage: drop "|| state_index.zero?" in DataBinding.enter_state; the
  # assert_equal on a fails, as the root binds again over the host's value.
  def test_entering_the_root_or_under_early_binding_binds_nothing
    late = chart("late")
    started = B.start(context({ "a" => "host" }, machine: late))

    assert_equal "host", B.enter_state(D.context(started.data, late, [0]), 0).data["a"]
    assert_same U, B.enter_state(context(machine: chart("early")), 1).data.fetch("e", U)
  end

  # sabotage: build one context per <data> from the accumulating data in
  # DataBinding.bind_all; the assert_same on b fails, as b reads a.
  def test_one_pass_reads_the_datamodel_as_it_stood_before_the_pass
    chained = machine('<datamodel><data id="a" expr="1"/><data id="b" expr="a"/></datamodel>')

    assert_same U, B.start(context(machine: chained)).data["b"]
  end
end
