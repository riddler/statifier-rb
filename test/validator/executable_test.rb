# frozen_string_literal: true

require "test_helper"
require_relative "validator_helper"

# The gating checks of executable content and `<invoke>`, the check of the
# markup, and the one warning: each finding's reason, detail and position,
# as the reference reports them for the same chart.
class ValidatorExecutableTest < Minitest::Test
  include ValidatorHelper

  # sabotage: stop the walk at the top level (answer [node] from
  # Executable.descend); the assert_equal fails on the assign in the
  # foreach.
  def test_an_assign_with_expr_carries_no_child_content
    source = doc(cat(%(<state id="s"><onentry><assign location="x" expr="1">t</assign><assign location="y" expr="2">),
                     %(<a/></assign><if cond="c"><assign location="z" expr="3"> </assign><foreach array="a" item="i">),
                     %(<assign location="w" expr="4">u</assign></foreach></if></onentry></state>)))

    assert_equal [[:assign_expr_and_text, { expr: "1" }, 1, 85],
                  [:assign_expr_and_text, { expr: "2" }, 1, 125],
                  [:assign_expr_and_text, { expr: "4" }, 1, 249]], errors_of(source)
  end

  # sabotage: report every branch after the first else as a duplicate
  # (always :if_duplicate_else in Executable.ifs); the assert_equal fails.
  def test_an_else_comes_last_and_once
    source = doc(cat(%(<state id="s"><onexit><if cond="a"><else/><elseif cond="b"/><else/></if></onexit>),
                     %(<transition><if cond="a"><elseif cond="b"/><else/><if cond="x"><else/><else/></if></if>),
                     %(</transition></state>)))

    assert_equal [[:if_elseif_after_else, {}, 1, 104],
                  [:if_duplicate_else, {}, 1, 122],
                  [:if_duplicate_else, {}, 1, 213]], errors_of(source)
  end

  # sabotage: leave out the root's scripts (drop `+ document.scripts` in
  # Executable.scripts); the assert_equal fails.
  def test_a_script_has_a_program
    source = doc(cat(%(<script/><script>  </script><script>x</script><state id="s"><onentry><script/></onentry>),
                     %(<initial><transition target="t"><script> </script></transition></initial><state id="t"/>),
                     %(</state>)))

    assert_equal [[:script_no_src_or_text, {}, 1, 62], [:script_no_src_or_text, {}, 1, 71],
                  [:script_no_src_or_text, {}, 1, 131], [:script_no_src_or_text, {}, 1, 182]], errors_of(source)
  end

  # sabotage: test only `src` against a `<content>` (`node.src` for
  # `(node.src || node.srcexpr)` in INVOKE_RULES); the assert_equal fails
  # on the second invoke.
  def test_an_invoke_writes_one_of_each_exclusive_pair
    source = doc(cat(%(<state id="s"><invoke type="a" typeexpr="b" src="c" srcexpr="d" id="e" idlocation="f" ),
                     %(namelist="g"><param name="p" expr="1"/><content>x</content></invoke><invoke srcexpr="d">),
                     %(<content/></invoke></state>)))

    assert_equal [[:invoke_type_and_typeexpr, {}, 1, 76], [:invoke_src_and_srcexpr, {}, 1, 76],
                  [:invoke_src_and_content, {}, 1, 76], [:invoke_id_and_idlocation, {}, 1, 76],
                  [:invoke_namelist_and_param, {}, 1, 76], [:invoke_src_and_content, {}, 1, 216]], errors_of(source)
  end

  # sabotage: accept only the bare spelling of the internal target
  # (`INTERNAL = %w[_internal]`); the assert_equal fails on the hashed
  # target.
  def test_a_send_writes_one_of_each_exclusive_pair
    source = doc(cat(%(<state id="s"><onentry><send event="a" eventexpr="b" target="c" targetexpr="d" type="e" ),
                     %(typeexpr="f" id="g" idlocation="h" delay="1s" delayexpr="i"/><send target="_internal" ),
                     %(delay="1s"/><send target="#_internal" delayexpr="d"/><send targetexpr="t" delay="1s"/>),
                     %(<send namelist="a"><param name="p" expr="1"/><content/></send></onentry></state>)))

    assert_equal [[:send_event_and_eventexpr, {}, 1, 85], [:send_target_and_targetexpr, {}, 1, 85],
                  [:send_type_and_typeexpr, {}, 1, 85], [:send_id_and_idlocation, {}, 1, 85],
                  [:send_delay_and_delayexpr, {}, 1, 85], [:send_delay_and_internal_target, {}, 1, 211],
                  [:send_delay_and_internal_target, {}, 1, 248], [:send_namelist_and_content, {}, 1, 322],
                  [:send_param_and_content, {}, 1, 322]], errors_of(source)
  end

  # sabotage: leave out the finalize blocks (drop `+ finalize_nodes(_1)`
  # in Executable.cancels); the assert_equal fails.
  def test_a_cancel_writes_exactly_one_of_sendid_and_sendidexpr
    source = doc(cat(%(<state id="s"><onentry><cancel/><cancel sendid="a" sendidexpr="b"/><cancel sendid="c"/>),
                     %(</onentry><invoke><finalize><cancel/><if cond="c"><cancel/></if></finalize></invoke></state>)))

    assert_equal [[:cancel_no_sendid, {}, 1, 85], [:cancel_sendid_and_sendidexpr, {}, 1, 94],
                  [:cancel_no_sendid, {}, 1, 177], [:cancel_no_sendid, {}, 1, 199]], errors_of(source)
  end

  # sabotage: read only the root's attributes (answer `own` without the
  # children in Attributes.element_duplicates); the assert_equal fails.
  def test_an_attribute_appears_once_on_a_tag
    source = doc(cat(%(<state id="s" id="t"><onentry><raise event="e" event="f" event="g"/></onentry><invoke>),
                     %(<content><x a="1" a="2"/></content></invoke></state>)))

    assert_equal [[:duplicate_attribute, { element: "state", attribute: "id" }, 1, 76],
                  [:duplicate_attribute, { element: "raise", attribute: "event" }, 1, 109],
                  [:duplicate_attribute, { element: "raise", attribute: "event" }, 1, 119],
                  [:duplicate_attribute, { element: "x", attribute: "a" }, 1, 166]], errors_of(source)
  end

  # sabotage: warn of a `<send>` only (drop Document::Raise from
  # FORBIDDEN_IN_FINALIZE); the assert_equal on the warnings fails.
  def test_a_raise_or_send_inside_finalize_is_a_warning_that_does_not_gate
    source = doc(cat(%(<state id="s"><invoke><finalize><raise event="e"/><send event="f" eventexpr="g"/>),
                     %(<foreach array="a" item="i"><raise event="h"/></foreach><log expr="1"/></finalize>),
                     %(</invoke></state>)))
    warned = validate(doc(%(<state id="s"><invoke><finalize><raise event="e"/></finalize></invoke></state>)))

    assert_equal [[:finalize_forbidden_content, { element: "raise" }, 1, 94],
                  [:finalize_forbidden_content, { element: "send" }, 1, 112],
                  [:finalize_forbidden_content, { element: "raise" }, 1, 171]], warnings_of(source)
    assert_equal [[:send_event_and_eventexpr, {}, 1, 112]], errors_of(source)
    assert_predicate warned, :ok?
    assert_equal ["<raise> must not occur inside <finalize>"], warned.warnings.map(&:message)
  end
end
