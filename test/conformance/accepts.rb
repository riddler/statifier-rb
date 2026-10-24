# frozen_string_literal: true

require "json"
require_relative "../../lib/statifier"

module Conformance
  # The accepts check a case's host object asks for, compared as the
  # reference's harness compares it (`accepts/2` in
  # lib/mix/statifier/corpus/host_case.ex): `declared_events` and
  # `expect_accepts` present together or not at all, and
  # {Statifier.check_accepts}'s two lists for the compiled chart exactly
  # `expect_accepts`' `unreachable` and `undeclared`, order included.
  module Accepts
    # The case's source compiled and its accepts check compared, before the
    # chart starts: `[machine, reason]`, the reason nil when the source
    # compiles and the check agrees.
    def self.prepared(item)
      compiled = Statifier.compile(item.fetch("source"))
      return [nil, "the source does not compile: #{compiled.error.map { "#{_1.reason}: #{_1.message}" }.join("; ")}"] \
        unless compiled.ok?

      [compiled.value, disagreement(compiled.value, item.fetch("host", {}))]
    end

    # The disagreement with the host object, or nil: either key without the
    # other, or the check's two lists other than exactly `expect_accepts`.
    def self.disagreement(machine, host)
      declared = host.key?("declared_events")
      expected = host.key?("expect_accepts")
      return unless declared || expected
      return "declared_events is present without expect_accepts" unless expected
      return "expect_accepts is present without declared_events" unless declared

      compare(Statifier.check_accepts(machine, host["declared_events"]), host["expect_accepts"])
    end

    # The check against the expected lists: nil when they are equal.
    def self.compare(check, expected)
      actual = { "unreachable" => check.unreachable, "undeclared" => check.undeclared }
      return if actual == expected

      "expected the accepts check #{JSON.generate(expected)}, but got #{JSON.generate(actual)}"
    end
  end
end
