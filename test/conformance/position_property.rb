# frozen_string_literal: true

require "json"
require_relative "runner"
require_relative "position_compare"

module Conformance
  # The position round-trip property, a claim of this package about itself
  # over the scion suite: nothing a position carries is lost on the way out
  # and back in.
  #
  # Each case is driven as the drive drives it (Drive in runner.rb: the
  # settle window before each event, the configuration deadline after it),
  # and a POINT is taken after the start and after every step. At each
  # point the state's position is exported ({Statifier.export_position}),
  # written to JSON text and read back, and imported
  # ({Statifier.import_position}) into a fresh compile of the case's source;
  # the remaining steps are then driven on the imported state the same way.
  # The imported state must agree with the unbroken drive's at the point and
  # after every later step (`disagreement` says what is compared).
  #
  # A point whose state a position cannot carry is counted with its reason
  # rather than compared: the export's own refusals, and the driver's own
  # members a position does not hold (a pending timer, an external event
  # not yet taken, a send a processor holds, a budget halt), each of which
  # an import starts empty, so the continuation would be another drive. Two
  # reasons are expected, a pending timer and an internal event waiting;
  # `stage_failures` fails a run with any other, and a run where no point
  # agrees, since a property that compared nothing proves nothing.
  #
  # The claim says nothing about whether a position matches the
  # reference's; a step's `expect_position` in the statifier suite states
  # that, and the drive does not compare it yet.
  module PositionProperty
    # The reasons a point may go uncarried with the stage passing.
    EXPECTED_NOT_CARRIED = %i[internal_queue_not_empty pending_timers].freeze

    # The property's counts over a run, and every disagreement: each a
    # `[case id, point, reason]`.
    Report = ::Data.define(:cases, :steps, :points, :agreeing, :not_carried, :disagreements)

    # What one point came to: `outcome` `:agree`, `:not_carried` or
    # `:disagree`, with its `reason` for the last two.
    Point = ::Data.define(:case_id, :point, :outcome, :reason)

    # The scion suite's cases.
    def self.scion(corpus = Corpus.load) = corpus.cases.select { _1["suite"] == "scion" }

    # The property over `cases`. `export` answers a position for a driver
    # state as {Statifier.export_position} does; a planted one tests that
    # the property catches a lost field.
    def self.run(cases, export: Statifier.method(:export_position))
      points = cases.flat_map { round_trips(_1, export) }
      outcomes = points.group_by(&:outcome)
      Report.new(cases: cases.size, steps: cases.sum { _1["steps"].size }, points: points.size,
                 agreeing: outcomes.fetch(:agree, []).size, **tallied(outcomes))
    end

    # The uncarried points counted by reason, and each disagreement.
    def self.tallied(outcomes)
      { not_carried: outcomes.fetch(:not_carried, []).map(&:reason).tally,
        disagreements: outcomes.fetch(:disagree, []).map { [_1.case_id, _1.point, _1.reason] } }
    end

    # Every point of one case: the start (point 0), then after each step.
    def self.round_trips(item, export)
      states = unbroken(item)
      states.each_index.map { round_trip(item, states, _1, export) }
    end

    # The drive's state after the start and after each step.
    def self.unbroken(item)
      state = Drive.moved(Statifier.start(compiled(item), session_id: item.fetch("id")))
      states = [Drive.await(state, item.fetch("initial_configuration"), 0)]
      item.fetch("steps").each { states << step(states.last, _1) }
      states
    end

    # One step driven as the drive drives it; a refused step raises,
    # which the property reports as the point's disagreement.
    def self.step(state, step)
      state = Drive.settle(state)
      since = state.now_ms
      Drive.await(Drive.moved(Statifier.step(state, step.fetch("event").fetch("name"))), step.fetch("configuration"),
                  since)
    end

    # The case's source compiled afresh.
    def self.compiled(item)
      compiled = Statifier.compile(item.fetch("source"))
      raise "#{item["id"]}: the source does not compile" unless compiled.ok?

      compiled.value
    end

    # The point after `point` steps: exported, carried through JSON,
    # imported into a fresh compile and driven on.
    def self.round_trip(item, states, point, export)
      original = states[point]
      exported = export.call(original)
      return point(item, point, :not_carried, exported.error.reason) unless exported.ok?

      held = driver_held(original)
      return point(item, point, :not_carried, held) if held

      reason = continued(item, states, point, JSON.parse(JSON.generate(exported.value)))
      point(item, point, reason ? :disagree : :agree, reason)
    end

    # The first disagreement of the imported drive, or nil.
    def self.continued(item, states, point, position)
      imported = Statifier.import_position(compiled(item), position)
      return "the import was refused: #{imported.error.reason}" unless imported.ok?

      stopped = !states[point].done.nil?
      state = imported.value
      found = PositionCompare.disagreement(states[point], state, stopped)
      return "at the import: #{found}" if found

      continue_steps(item, states, point, state, stopped)
    rescue RuntimeError => e
      "the imported drive raised: #{e.message}"
    end

    # The remaining steps on the imported state, compared after each.
    def self.continue_steps(item, states, point, state, stopped)
      ((point + 1)...states.size).each do |later|
        state = step(state, item.fetch("steps")[later - 1])
        found = PositionCompare.disagreement(states[later], state, stopped)
        return "step #{later}: #{found}" if found
      end
      nil
    end

    # What a position does not carry of `state`'s, or nil.
    def self.driver_held(state)
      return :pending_timers unless state.timers.empty?
      return :external_queue_not_empty unless state.external_queue.empty?
      return :held_sends unless state.held_sends.empty?

      :halted unless state.halted.nil?
    end

    # One point's result.
    def self.point(item, point, outcome, reason) = Point.new(case_id: item.fetch("id"), point:, outcome:, reason:)

    # Why the gate stage fails `report` beyond its disagreements, one line
    # each: no point agreed, or a point went uncarried for a reason outside
    # EXPECTED_NOT_CARRIED.
    def self.stage_failures(report)
      failures = []
      failures << "position: no round trip agrees over #{report.points} points" if report.agreeing.zero?
      report.not_carried.except(*EXPECTED_NOT_CARRIED).sort.each do |reason, count|
        failures << "position: #{count} points not carried for #{reason}"
      end
      failures
    end

    # The report's summary lines.
    def self.lines(report)
      ["position: #{report.points} points over #{report.cases} scion cases " \
       "(#{report.cases} starts and #{report.steps} steps)",
       "position: #{report.agreeing} round trips agree, #{report.disagreements.size} disagree",
       "position: #{report.not_carried.values.sum} points not carried#{reasons(report)}",
       *report.disagreements.map { |id, point, reason| "  - #{id} at point #{point}: #{reason}" }]
    end

    # Each reason a point was not carried, with its count, after a colon;
    # empty when every point was carried.
    def self.reasons(report)
      return "" if report.not_carried.empty?

      ": #{report.not_carried.sort.map { |reason, count| "#{reason} #{count}" }.join(", ")}"
    end
  end
end
