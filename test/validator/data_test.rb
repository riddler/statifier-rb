# frozen_string_literal: true

require "test_helper"
require_relative "validator_helper"

# The gating checks of the root, the enumerated values, `<donedata>`,
# `<content>`, `<param>` and `<data>`: each error's reason, detail and
# position, as the reference reports them for the same chart.
class ValidatorDataTest < Minitest::Test
  include ValidatorHelper

  # sabotage: allow `<donedata>` anywhere (`carriers.reject { true }` for
  # the first list in DataChecks.donedata); the assert_equal fails.
  def test_donedata_sits_on_a_final_and_holds_content_or_params
    source = doc(cat(%(<state id="a"><donedata/></state><final id="f"><donedata><content>x</content>),
                     %(<param name="p" expr="1"/></donedata></final>)))

    assert_equal [[:donedata_not_on_final, { id: "a" }, 1, 76],
                  [:donedata_content_and_params, { id: "f" }, 1, 109]], errors_of(source)
  end

  # sabotage: count blank text as a payload (drop the blank? test in
  # DataChecks.payload); the assert_equal on the reasons fails.
  def test_a_content_with_expr_carries_no_markup_or_text
    source = doc(cat(%(<final id="f"><donedata><content expr="1">t</content></donedata></final><state id="s">),
                     %(<invoke><content expr="2"><x/></content></invoke><invoke><content expr="3">  </content>),
                     %(</invoke></state>)))
    errors = validate(source).errors

    assert_equal [[:content_expr_and_text, { expr: "1" }, 1, 86],
                  [:content_expr_and_text, { expr: "2" }, 1, 156]], rows(errors)
    assert_equal ['<content> must not specify both an expr attribute ("1") and inline text',
                  '<content> must not specify both an expr attribute ("2") and inline markup'], errors.map(&:message)
  end

  # sabotage: skip the params of a send (drop the Executable.sends term in
  # DataChecks.params); the assert_equal fails on the send's param.
  def test_a_param_writes_exactly_one_of_expr_and_location
    source = doc(cat(%(<final id="f"><donedata><param name="a"/><param name="b" expr="1" location="x"/>),
                     %(</donedata></final><state id="s"><invoke><param name="c"/></invoke><onentry>),
                     %(<send event="e"><param name="d"/></send></onentry></state>)))

    assert_equal [[:param_no_value, { name: "a" }, 1, 86],
                  [:param_expr_and_location, { name: "b" }, 1, 103],
                  [:param_no_value, { name: "c" }, 1, 183],
                  [:param_no_value, { name: "d" }, 1, 234]], errors_of(source)
  end

  # sabotage: relax the version with the namespace (`||
  # context.invoke_content_markup` on the version guard in
  # Enums.boilerplate); the assert_equal under the option fails.
  def test_the_root_is_in_the_scxml_namespace_at_version_one
    prefixed = %(<s:scxml xmlns:s="#{Internals::Lowering::SCXML_NAMESPACE}" version="1.0"><s:state id="a"/></s:scxml>)

    assert_equal [[:bad_namespace, { uri: nil }, 1, 1], [:bad_version, { version: nil }, 1, 1]],
                 errors_of(%(<scxml><state id="a"/></scxml>))
    assert_equal [[:bad_version, { version: "2.0" }, 1, 57]],
                 errors_of(%(<scxml xmlns="#{Internals::Lowering::SCXML_NAMESPACE}" version="2.0"/>))
    assert_empty errors_of(prefixed)
    assert_empty errors_of(%(<scxml version="1.0"/>), invoke_content_markup: true)
    assert_equal [[:bad_version, { version: "2" }, 1, 17]],
                 errors_of(%(<scxml version="2"/>), invoke_content_markup: true)
  end

  # sabotage: accept every written value (`true` for allowed.include?(raw)
  # in Enums.out_of_range); the first assert_equal fails.
  def test_enumerated_values_are_in_range_as_written
    source = doc(cat(%(<state id="a"><transition type="sideways" target="a"/><transition type="internal" target="a"/>),
                     %(<invoke autoforward="yes"/><invoke autoforward="true"/></state>)),
                 %(#{ROOT} binding="whenever" datamodel="javascript"))

    assert_equal [[:scxml_bad_binding, { raw: "whenever" }, 1, 71],
                  [:scxml_bad_datamodel, { raw: "javascript" }, 1, 92],
                  [:transition_bad_type, { raw: "sideways" }, 1, 136],
                  [:invoke_bad_autoforward, { raw: "yes" }, 1, 219]], errors_of(source)
    assert_empty errors_of(doc(%(<state id="a"/>), %(#{ROOT} binding="late" datamodel="ecmascript")))
  end

  # sabotage: accept a datamodel on a history (drop :history from
  # DataChecks.misplaced_datamodels); the assert_equal fails.
  def test_data_and_datamodel_placement
    source = doc(cat(%(<datamodel><data id="d1" expr="1" src="x"/><data id="_d" expr="1">text</data>),
                     %(<data id="d3" src="y">  </data></datamodel><final id="f"><datamodel/></final><state id="s">),
                     %(<history id="h"><datamodel/><transition target="s1"/></history><state id="s1"/></state>)))

    assert_equal [[:data_expr_and_src, { id: "d1" }, 1, 83],
                  [:data_value_and_children, { id: "_d" }, 1, 115],
                  [:data_reserved_id, { id: "_d" }, 1, 115],
                  [:datamodel_bad_parent, { kind: :final }, 1, 196],
                  [:default_entry_not_enterable, { id: "s", child_kind: :history }, 1, 230],
                  [:datamodel_bad_parent, { kind: :history }, 1, 246]], errors_of(source)
  end
end
