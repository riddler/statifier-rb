# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# The HTTP side of the package is opt-in: `require "statifier"` loads no
# HTTP library and none of `Statifier::BasicHTTP`, and only
# `require "statifier/basichttp"` loads them, the processor among them. Each is asked of a fresh Ruby
# process, since this suite's own process loads both.
class BasicHTTPLoadTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)

  PROBE = <<~RUBY
    require ARGV.fetch(0)
    puts [
      $LOADED_FEATURES.any? { |path| path.end_with?("/net/http.rb") },
      !defined?(Net::HTTP).nil?,
      Statifier.const_defined?(:BasicHTTP, false) && Statifier::BasicHTTP.const_defined?(:Processor, false)
    ].inspect
  RUBY

  # What a fresh process that requires `feature` has loaded: net/http,
  # Net::HTTP and Statifier::BasicHTTP with its processor, in that order.
  def loaded_after(feature)
    out, status = Open3.capture2e(RbConfig.ruby, "-I", LIB, "-e", PROBE, feature)
    assert_predicate status, :success?, out
    out.lines.last.strip
  end

  # sabotage: add `require_relative "statifier/basichttp"` to the end of lib/statifier.rb; the core then loads net/http.
  def test_the_core_loads_no_http_library
    assert_equal "[false, false, false]", loaded_after("statifier")
  end

  # sabotage: drop `require "net/http"` from net_http_transport.rb; Net::HTTP is then not loaded.
  def test_the_opt_in_require_loads_the_transport
    assert_equal "[true, true, true]", loaded_after("statifier/basichttp")
  end
  # A chart compiled, started and stepped by a process that loaded the core
  # alone; it then reports its configuration and whether net/http or
  # Statifier::BasicHTTP was loaded on the way.
  CORE_RUN = <<~RUBY
    require "statifier"
    machine = Statifier.compile(<<~SCXML).value
      <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0">
        <state id="a"><transition event="e.go" target="b"/></state>
        <final id="b"/>
      </scxml>
    SCXML
    started = Statifier.start(machine, session_id: "s1").value
    stepped = Statifier.step(started.state, "e.go").value
    puts [
      Statifier.done?(stepped.state).value.configuration,
      $LOADED_FEATURES.any? { |path| path.end_with?("/net/http.rb") },
      Statifier.const_defined?(:BasicHTTP, false)
    ].inspect
  RUBY

  # sabotage: add `require_relative "statifier/basichttp"` after the requires of lib/statifier.rb; BasicHTTP is loaded.
  def test_the_core_runs_a_chart_with_the_processor_absent
    out, status = Open3.capture2e(RbConfig.ruby, "-I", LIB, "-e", CORE_RUN)

    assert_predicate status, :success?, out
    assert_equal '[["b"], false, false]', out.lines.last.strip
  end
end
