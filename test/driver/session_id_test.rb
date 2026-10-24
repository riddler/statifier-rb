# frozen_string_literal: true

require "test_helper"
require_relative "driver_helper"

# The session id: the host's, copied and frozen, or one the driver mints in
# the reference's shape.
class SessionIdTest < Minitest::Test
  include DriverHelper

  # sabotage: answer `SessionId.mint` whatever the host named in
  # Checks.session_id; the assert_equal on the named id fails.
  def test_the_session_id_is_the_host_s_or_one_the_driver_mints
    body = %(<state id="a"><onentry><log label="sid" expr="_sessionid"/></onentry></state>)
    minted = moved(Statifier.start(machine(body))).effects.grep(E::Log).first.value

    assert_equal [%w[sid s1]], logs(start(body))
    assert_match(/\Asess_[0-9a-hjkmnp-tv-z]{26}\z/, minted)
  end

  # sabotage: answer `session_id` uncopied in Checks.session_id; the
  # assert_equal on the answered state's session id fails once the host
  # changes its string.
  def test_a_host_s_session_id_is_copied_so_changing_it_changes_no_answered_state
    sid = +"s1"
    started = moved(Statifier.start(machine(<<~XML), session_id: sid))
      <state id="a"><transition event="e.go"><send event="e.self" target="#_scxml_s1"/></transition>
        <transition event="e.self" target="b"/><transition event="error.*" target="fail"/></state>
      <state id="b"/><state id="fail"/>
    XML
    sid.replace("zz")

    assert_equal ["s1", %w[b]], [started.state.session_id, active(step(started, "e.go"))]
    refute_predicate sid, :frozen?
  end

  # sabotage: answer `SessionId.mint` unfrozen in Checks.session_id; the
  # assert_predicate on the minted id fails.
  def test_a_minted_session_id_is_frozen
    assert_predicate moved(Statifier.start(machine(%(<state id="a"/>)))).state.session_id, :frozen?
  end

  # sabotage: drop the `<< 2` padding in SessionId.encode; the assert_equal
  # on the encoded value fails.
  def test_a_minted_id_is_the_reference_s_unpadded_base32_of_sixteen_bytes
    assert_equal "sess_#{"0" * 25}4", Statifier::Driver::SessionId.encode(1)
    assert_equal "sess_z#{"0" * 25}", Statifier::Driver::SessionId.encode(31 << 123)
  end
end
