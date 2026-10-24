# frozen_string_literal: true

require_relative "corpus"
require_relative "../../lib/statifier"

module Conformance
  # THE SEAM: what the run does with one case. It is the one place the
  # library is plugged into the run; the runner, the registry check and the
  # ratchet all reach the library through Drive.call and nothing else.
  #
  # A drive takes a case (one element of a suite file's cases, as the JSON
  # parser gives it) and answers :pass, or a String saying why the case
  # failed. Anything other than :pass is a fail, and a drive that raises is a
  # fail naming the exception: a case is never skipped and never aborts the
  # run.
  #
  # The drive is the one the copy's RATCHET.md describes under "What a case
  # asserts", through the driver ({Statifier.start}, {Statifier.step} and
  # {Statifier.advance}): compile the case's source, start it and compare
  # the active leaf states with initial_configuration, then for each step
  # settle the virtual clock, send the step's event and compare with the
  # step's configuration. It compares the active leaf set - the active states
  # with no child, by id - as the reference's harness does
  # (`assert_configuration/3` and `active_leaf_states/1` in
  # lib/statifier/testing/case.ex); an active leaf with no id fails the case,
  # as the reference's `assert_every_leaf_named/2` does. A stopped chart is
  # compared at the configuration it stopped in. Only the event's name is
  # sent, as the reference's harness sends only the name.
  #
  # The virtual clock, in the reference harness's two knobs
  # (`@default_settle_window_ms` and `@default_configuration_deadline_ms` in
  # lib/statifier/testing/case.ex), as statifier-ts's runner reads them on a
  # virtual clock:
  #
  # - The settle window. Before each event, while a timer is pending and the
  #   earliest falls due within SETTLE_WINDOW_MS of the window's start, the
  #   clock moves to that due time, firing it and every timer due then; a
  #   timer due later stays pending, and the clock ends the window at its
  #   end. When no timer is left the clock stays where the last one fired.
  # - The configuration deadline. After the start and after each event,
  #   while the active leaf set differs from the expectation, the chart runs
  #   and a timer is pending whose due time is within
  #   CONFIGURATION_DEADLINE_MS of the event, the clock moves to the earliest
  #   due time and fires what is due; the comparison is made once none of
  #   that holds.
  #
  # The clock only ever moves to a due time, because nothing but a firing
  # timer changes the configuration between two events. A case carrying a
  # host object, or a step stating an exported position, asks for what this
  # runner does not honour yet, and fails with that named.
  module Drive
    # How long, in virtual ms, the clock may run before an event to drain
    # short timers.
    SETTLE_WINDOW_MS = 100

    # How long, in virtual ms after an event, the drive waits for the
    # expectation.
    CONFIGURATION_DEADLINE_MS = 4000

    # The answer for item: :pass, or the reason it failed.
    def self.call(item)
      unhonoured = unhonoured(item)
      return unhonoured if unhonoured

      compiled = Statifier.compile(item.fetch("source"))
      return "the source does not compile: #{compiled.error.map { "#{_1.reason}: #{_1.message}" }.join("; ")}" \
        unless compiled.ok?

      drive(item, compiled.value)
    end

    # What the case asks of its host that this runner does not honour, or
    # nil.
    def self.unhonoured(item)
      return "the case's host object (#{item["host"].keys.join(", ")}) is not honoured here" if item.key?("host")
      return unless item.fetch("steps").any? { _1.key?("expect_position") }

      "a step states an exported position, which this package does not export"
    end

    # The start and every step, compared in turn.
    def self.drive(item, machine)
      state = moved(Statifier.start(machine, session_id: item.fetch("id")))
      state = await(state, item.fetch("initial_configuration"), 0)
      failed = compare(state, item.fetch("initial_configuration"), "the initial configuration")
      return failed if failed

      item.fetch("steps").each_with_index do |step, index|
        state, failed = drive_step(state, step, index)
        return failed if failed
      end
      :pass
    end

    # One step: the clock settled, the event sent, the expectation awaited
    # and compared. `[state, reason]`, the reason nil when it agrees.
    def self.drive_step(state, step, index)
      state = settle(state)
      since = state.now_ms
      name = step.fetch("event").fetch("name")
      state = await(moved(Statifier.step(state, name)), step.fetch("configuration"), since)
      [state, compare(state, step.fetch("configuration"), "step #{index + 1} (event #{name.inspect})")]
    end

    # The state a call answered; a refused call is a bug here, since every
    # call is handed a state the driver made.
    def self.moved(result)
      raise "the driver refused the call: #{result.error.inspect}" unless result.ok?

      result.value.state
    end

    # The earliest due time of a pending timer, or nil.
    def self.earliest_due(state) = state.timers.map(&:due_ms).min

    # The settle window.
    def self.settle(state)
      window_end = state.now_ms + SETTLE_WINDOW_MS
      loop do
        due = earliest_due(state)
        return state if due.nil?
        return moved(Statifier.advance(state, window_end - state.now_ms)) if due > window_end

        state = moved(Statifier.advance(state, due - state.now_ms))
      end
    end

    # The configuration deadline after `since`.
    def self.await(state, expected, since)
      deadline = since + CONFIGURATION_DEADLINE_MS
      loop do
        return state if leaves(state) == expected.sort || !state.done.nil?

        due = earliest_due(state)
        return state if due.nil? || due > deadline

        state = moved(Statifier.advance(state, due - state.now_ms))
      end
    end

    # The active leaf states by id, sorted, a stopped chart's as it stopped;
    # an Integer counting the leaves with no id when there are any.
    def self.leaves(state)
      machine = state.machine_state.machine
      atomic = active(state).select { machine.atomic?(_1) && !_1.zero? }
      unnamed = atomic.count { machine.state(_1).id.nil? }
      unnamed.positive? ? unnamed : atomic.map { machine.state(_1).id }.sort
    end

    # The active state indexes, a stopped chart's as it stopped.
    def self.active(state) = state.done.nil? ? state.machine_state.configuration : state.done.configuration

    # nil when the leaves agree with `expected`, else the reason.
    def self.compare(state, expected, where)
      found = leaves(state)
      return "#{where}: #{found} active leaf state(s) have no id; the expectation cannot name them" \
        if found.is_a?(Integer)
      return if found == expected.sort

      "#{where}: expected active leaf states #{expected.sort}, got #{found}"
    end
  end

  # The run: every case of every suite, each answered pass or fail. There is
  # no skip list and no third result.
  module Runner
    # The results of one run over corpus, by case id in corpus order: each
    # {"result" => "pass"} or {"result" => "fail", "reason" => ...}. drive is
    # anything answering call(item) as Drive does.
    def self.run(corpus, drive: Drive)
      corpus.cases.to_h { |item| [item.fetch("id"), result_for(item, drive)] }
    end

    def self.result_for(item, drive)
      answer = drive.call(item)
      return { "result" => "pass" } if answer == :pass

      { "result" => "fail", "reason" => answer.to_s }
    rescue StandardError => e
      { "result" => "fail", "reason" => "raised #{e.class}: #{e.message}" }
    end
    private_class_method :result_for

    # One line per suite: how many of its cases this package's registry
    # (entries, its entries) does not claim, and how many of those the
    # reference's registry (reference, its entries) claims.
    def self.unclaimed_lines(corpus, entries, reference)
      claimed = entries.to_h { |entry| [entry["case_id"], true] }
      theirs = reference.to_h { |entry| [entry["case_id"], true] }
      corpus.suites.map { |suite| unclaimed_line(suite, claimed, theirs) }
    end

    def self.unclaimed_line(suite, claimed, theirs)
      open = suite["cases"].map { |item| item["id"] }.reject { |id| claimed.key?(id) }
      "conformance: #{suite["suite"]}: #{open.size} of #{suite["cases"].size} cases not yet claimed " \
        "(the reference claims #{open.count { |id| theirs.key?(id) }} of them)"
    end
    private_class_method :unclaimed_line

    # The gap list: one line per case this package's registry (entries, its
    # entries) does not claim, in the reference's order (the manifest's
    # suites, each suite's cases as the file lists them): the case, the
    # features it needs (its required_features) and where it stands in
    # results (Runner.run's), either "passes" or "fails" with why. A case
    # that passes is on the list until the ratchet claims it.
    def self.gap_lines(corpus, entries, results)
      claimed = entries.to_h { |entry| [entry["case_id"], true] }
      corpus.cases.filter_map do |item|
        next if claimed.key?(item.fetch("id"))

        "conformance: gap: #{item["id"]} (needs #{needs(item)}): #{standing(results.fetch(item.fetch("id")))}"
      end
    end

    def self.needs(item)
      features = Array(item["required_features"])
      features.empty? ? "no feature" : features.join(", ")
    end
    private_class_method :needs

    def self.standing(result)
      result["result"] == "pass" ? "passes, not yet claimed" : "fails: #{result["reason"]}"
    end
    private_class_method :standing
  end
end
