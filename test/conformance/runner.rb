# frozen_string_literal: true

require_relative "corpus"
require_relative "host"
require_relative "accepts"
require_relative "position_expectation"
require_relative "../../lib/statifier"

module Conformance
  # The driver's calls as a drive makes them: with the processors the
  # drive registers, and, with a host, each answered state handed to the
  # host to report the sends the call handed that it marked failed
  # (Host#report), before anything reads it.
  Calls = ::Data.define(:machine, :processors, :host) do
    # The calls with no processor and no host.
    def self.plain = new(machine: nil, processors: {}, host: nil)

    def start(session_id) = after(Statifier.start(machine, session_id:, processors:))

    def step(state, name, data) = after(Statifier.step(state, name, data:, processors:))

    def advance(state, milliseconds) = after(Statifier.advance(state, milliseconds, processors:))

    # The state a call answered, the host's reports made.
    def after(result)
      state = Drive.moved(result)
      host.nil? ? state : host.report(machine, state, processors)
    end
  end

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
  # timer changes the configuration between two events.
  #
  # The host object. A case's `host.event_io_processors` names the Event I/O
  # Processors its host runs, by URI, as the reference's harness reads it
  # (`@event_io_processors` and `with_event_io_processors/2` in
  # lib/mix/statifier/corpus/host_case.ex). The drive registers with the
  # driver, on every call, each processor PROVIDED holds for a URI the case
  # names, under every send type that entry names, and fails a case naming a
  # URI PROVIDED holds no entry for, naming that URI.
  #
  # A case's `host.send_types` and `host.expect_sends` are read as the
  # reference's harness reads them (`run/2` and `handed/2` in
  # host_case.ex): a Host of the case's own (test/conformance/host.rb) is
  # registered under every type `send_types` names, beside the processors
  # above, from the start of the chart; once every configuration agrees,
  # the sends handed to it over the whole drive, in order and each with its
  # outcome, must be exactly `expect_sends`. A step of a case with a host
  # object, or of a case stating an exported position, sends its event's
  # `data`, when it gives one, as the harness injects it (the harness runs
  # both kinds of case through `run/2`). A send whose expected item asks the host to report it
  # failed (`"outcome": "fail"`) is reported through
  # {Statifier.report_send_failed} once each driver call that handed it
  # returns, before the configuration is read, as the harness reports it
  # through `Statifier.Session.failed_send/3` before it reads the next
  # configuration (`pump/3` in host_case.ex).
  #
  # A case's `host.declared_events` and `host.expect_accepts` are read as
  # the reference's harness reads them (`accepts/2` in host_case.ex),
  # present together or not at all: once the source compiles and before the
  # chart starts, {Statifier.check_accepts} answers for the compiled chart
  # and `declared_events`, and the case agrees only when its two lists are
  # exactly `expect_accepts`' `unreachable` and `undeclared`, order
  # included. Either key without the other fails the case, naming the one
  # present.
  #
  # A host object's diff pair, `to_source` and `expect_diff` with an
  # optional `mapping` and `expect_compatible_at`, is accepted and compared
  # by nothing here: a case carrying it is driven like any other host case,
  # as the reference's harness drives it (its moduledoc in host_case.ex:
  # "this runner compares none of them"). Any other host key (any key a
  # later corpus adds) is not honoured here and fails the case naming the
  # key.
  #
  # A step's `expect_position` is compared, once that step's configuration
  # agrees, with the rendering of the state's exported position
  # (Conformance::PositionExpectation, test/conformance/position_expectation.rb),
  # as the harness compares it (`position/3` in host_case.ex). A case that
  # states one on any step needs every state of its document to carry an id,
  # and fails before it is driven when one has none (`named/2` there).
  module Drive
    # How long, in virtual ms, the clock may run before an event to drain
    # short timers.
    SETTLE_WINDOW_MS = 100

    # How long, in virtual ms after an event, the drive waits for the
    # expectation.
    CONFIGURATION_DEADLINE_MS = 4000

    # The Event I/O Processors this package provides, by the URI a case's
    # `host.event_io_processors` names them under: each entry is a callable
    # answering a Hash of send type to processor (an object answering
    # `deliver`), every type the processor is registered under. It is empty
    # until the package provides a processor; a release that adds one adds
    # its entry here and nowhere else.
    PROVIDED = {}.freeze

    # The diff pair's host keys: accepted, and compared by nothing here.
    UNCOMPARED_HOST_KEYS = %w[to_source expect_diff mapping expect_compatible_at].freeze

    # The host keys the drive reads or accepts; any other is not honoured.
    HONOURED_HOST_KEYS = (%w[event_io_processors send_types expect_sends declared_events expect_accepts] +
                          UNCOMPARED_HOST_KEYS).freeze

    # The answer for item: :pass, or the reason it failed. provided is the
    # table of processors the drive can register (PROVIDED, unless a test
    # names another).
    def self.call(item, provided: PROVIDED)
      unhonoured = unhonoured(item, provided)
      return unhonoured if unhonoured

      machine, failed = Accepts.prepared(item)
      return failed if failed

      unnamed = PositionExpectation.expected?(item) && PositionExpectation.named(machine)
      return unnamed if unnamed

      host = Host.for(item)
      driven = drive(item, machine, host.processors.merge(registered(item, provided)), host)
      driven == :pass ? host.verdict : driven
    end

    # What the case asks of its host that this runner does not honour, or
    # nil: a host key it neither reads nor accepts, or a processor
    # `provided` holds no entry for.
    def self.unhonoured(item, provided = PROVIDED)
      host = item.fetch("host", {})
      other = host.keys - HONOURED_HOST_KEYS
      return "the case's host object (#{other.join(", ")}) is not honoured here" unless other.empty?

      not_provided(host, provided)
    end

    # The processors the host object names that `provided` holds no entry
    # for, as the reason, or nil.
    def self.not_provided(host, provided)
      missing = named(host).reject { provided.key?(_1) }
      return if missing.empty?

      "the case's host object names the Event I/O Processor #{missing.join(", ")}, " \
        "which this package does not provide"
    end

    # The URIs a host object's `event_io_processors` names, in order; a value
    # that is not a list is named whole, as it came, so it is refused.
    def self.named(host)
      value = host.fetch("event_io_processors", [])
      value.is_a?(Array) ? value : [value.inspect]
    end

    # The processors to hand the driver on every call for item: the send
    # types of every entry of `provided` the case names.
    def self.registered(item, provided)
      named(item.fetch("host", {})).each_with_object({}) { |uri, types| types.merge!(provided.fetch(uri).call) }
    end

    # The start and every step, compared in turn; processors go with every
    # call, as the driver asks, and a host reports its failed sends after
    # each.
    def self.drive(item, machine, processors = {}, host = nil)
      calls = Calls.new(machine:, processors:, host:)
      state = await(calls.start(item.fetch("id")), item.fetch("initial_configuration"), 0, calls)
      failed = compare(state, item.fetch("initial_configuration"), "the initial configuration")
      return failed if failed

      data = item.key?("host") || PositionExpectation.expected?(item)
      item.fetch("steps").each_with_index do |step, index|
        state, failed = drive_step(state, step, index, calls, host: data)
        return failed if failed
      end
      :pass
    end

    # One step: the clock settled, the event sent, the expectation awaited
    # and compared, and then the step's exported position when it states
    # one. `[state, reason]`, the reason nil when it agrees. A step of a
    # case the harness runs as a host case (`host`: one with a host object
    # or stating a position) sends its event's `data` when it gives one;
    # any other sends the name alone.
    def self.drive_step(state, step, index, calls = Calls.plain, host: false)
      state = settle(state, calls)
      since = state.now_ms
      event = step.fetch("event")
      name = event.fetch("name")
      data = host ? event.fetch("data", Predicator::UNDEFINED) : Predicator::UNDEFINED
      state = await(calls.step(state, name, data), step.fetch("configuration"), since, calls)
      failed = compare(state, step.fetch("configuration"), "step #{index + 1} (event #{name.inspect})")
      [state, failed || PositionExpectation.at_step(state, step, index + 1)]
    end

    # The state a call answered; a refused call is a bug here, since every
    # call is handed a state the driver made.
    def self.moved(result)
      raise "the driver refused the call: #{result.error.inspect}" unless result.ok?

      result.value.state
    end

    # The earliest due time of a pending timer, or nil: the session's own,
    # or one of an invoked child's, which run on the same clock.
    def self.earliest_due(state) = due_times(state).min

    # The due times of the pending timers of the session and its children.
    def self.due_times(state)
      state.timers.map(&:due_ms) + state.invocations.values.flat_map { due_times(_1.child) }
    end

    # The settle window.
    def self.settle(state, calls = Calls.plain)
      window_end = state.now_ms + SETTLE_WINDOW_MS
      loop do
        due = earliest_due(state)
        return state if due.nil?
        return calls.advance(state, window_end - state.now_ms) if due > window_end

        state = calls.advance(state, due - state.now_ms)
      end
    end

    # The configuration deadline after `since`.
    def self.await(state, expected, since, calls = Calls.plain)
      deadline = since + CONFIGURATION_DEADLINE_MS
      loop do
        return state if leaves(state) == expected.sort || !state.done.nil?

        due = earliest_due(state)
        return state if due.nil? || due > deadline

        state = calls.advance(state, due - state.now_ms)
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
