# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# The HTTP side of the package is opt-in: `require "statifier"` loads no
# HTTP library and none of `Statifier::BasicHTTP`, and only
# `require "statifier/basichttp"` loads them. Each is asked of a fresh Ruby
# process, since this suite's own process loads both.
class BasicHTTPLoadTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)

  PROBE = <<~RUBY
    require ARGV.fetch(0)
    puts [
      $LOADED_FEATURES.any? { |path| path.end_with?("/net/http.rb") },
      !defined?(Net::HTTP).nil?,
      Statifier.const_defined?(:BasicHTTP, false)
    ].inspect
  RUBY

  # What a fresh process that requires `feature` has loaded: net/http,
  # Net::HTTP and Statifier::BasicHTTP, in that order.
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
end
