# frozen_string_literal: true

require "test_helper"
require_relative "lowering_helper"

# The `<scxml>` root: its attributes, their defaults, the namespace and
# what it holds.
class LoweringRootTest < Minitest::Test
  include LoweringHelper

  # sabotage: read "version" for the name in States.scxml (the value of
  # "version" when the key is :name); the assert_equal on the fields fails.
  def test_reads_the_root_attributes_as_written
    document = chart(%(<scxml xmlns="#{SCXML}" name="n" version="1.0" datamodel="predicator" initial="a b"/>))

    assert_equal ["n", "1.0", "predicator", SCXML, SCXML, %w[a b]],
                 [document.name, document.version, document.datamodel, document.xmlns, document.namespace,
                  document.initial]
  end

  # sabotage: map "late" to :early in States::BINDINGS; the assert_equal
  # on :late fails.
  def test_binding_is_early_unless_written_late
    assert_equal :early, chart("<scxml/>").binding
    assert_equal :late, chart(%(<scxml binding="late"/>)).binding
    assert_equal :early, chart(%(<scxml binding="sideways"/>)).binding
  end

  # sabotage: key attribute_locations by every name asked for, written or
  # not (drop the `if found&.value_location` in Reading.locations); the
  # assert_equal on the keys fails.
  def test_records_the_value_spans_of_written_attributes_only
    source = %(<scxml binding="sideways" initial=""/>)
    locations = chart(source).attribute_locations

    assert_equal %i[initial binding], locations.keys
    assert_equal "sideways", slice(locations[:binding], source)
    assert_equal [1, 36, 35, 1, 36, 35], span_of(locations[:initial])
  end

  # sabotage: resolve the namespace from the xmlns attribute in
  # States.scxml (namespace: Reading.value(element, "xmlns")); the
  # assert_equal on the prefixed root's namespace fails.
  def test_a_prefixed_root_lowers_and_carries_the_namespace_it_resolves_to
    document = chart(%(<s:scxml xmlns:s="#{SCXML}"><s:state id="a"/></s:scxml>))

    assert_nil document.xmlns
    assert_equal SCXML, document.namespace
    assert_equal ["a"], document.states.map(&:id)
  end

  # sabotage: give a child element with no namespace no builder (BUILDERS
  # looked up only when element.namespace is set, in Lowering.walk_element);
  # the chart of the undeclared document is refused.
  def test_a_document_that_declares_no_namespace_lowers_as_its_declared_twin
    document = chart(%(<scxml><state id="a"/><p:state id="b"/></scxml>))

    assert_nil document.namespace
    assert_equal %w[a b], document.states.map(&:id)
  end

  # sabotage: give a root script no place (drop Document::Script from
  # States::ROOT_SLOTS); the chart is refused.
  def test_holds_states_in_document_order_its_scripts_and_its_last_datamodel
    document = chart_of(<<~XML)
      <state id="a"/><script>x</script><parallel id="b"/><datamodel><data id="d1"/></datamodel>
      <final id="c"/><datamodel><data id="d2"/></datamodel><script>y</script>
    XML

    assert_equal [%i[state parallel final], %w[a b c]], [document.states.map(&:kind), document.states.map(&:id)]
    assert_equal %w[x y], document.scripts.map(&:text)
    assert_equal ["d2"], document.datamodel_element.data.map(&:id)
  end

  # sabotage: split list attributes on every white space (add \u00a0 to
  # Reading::SPLIT); the first assert_equal fails.
  def test_splits_a_list_on_white_space_but_not_on_a_no_break_space
    assert_equal ["a\u00a0b", "c", "d"], chart(%(<scxml initial=" a\u00a0b\tc\u3000d "/>)).initial
    assert_equal [], chart(%(<scxml initial="  "/>)).initial
  end
end
