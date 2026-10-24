# frozen_string_literal: true

require_relative "machine"
require_relative "interpreter"

module Statifier
  # What {Statifier.check_accepts} answers: the declared names no descriptor
  # in the chart's event vocabulary matches, and the vocabulary's descriptors
  # that match no declared name. A frozen value, deeply.
  #
  # @!attribute [r] unreachable
  #   @return [Array<String>] each declared name no descriptor in the
  #     vocabulary matches, in the declaration's order and without
  #     duplicates: a name the declaration promises and the chart can never
  #     select on
  # @!attribute [r] undeclared
  #   @return [Array<String>] each descriptor in the vocabulary that matches
  #     no declared name, in the vocabulary's order: a name the chart listens
  #     for that the declaration does not state
  AcceptsCheck = ::Data.define(:unreachable, :undeclared)

  # The accepts check: a declaration of the event names a chart accepts,
  # compared with the chart's event vocabulary, as the reference compares
  # them (`Statifier.Chart.check_accepts/2` and the vocabulary it reads,
  # `Statifier.Chart.events/1`, in statifier-ex). {Statifier.check_accepts}
  # answers through this module.
  #
  # The vocabulary is every event descriptor on a transition whose source
  # state can be active, each returned as authored and a pattern never
  # expanded. "Can be active" is a static rule over the chart's structure: a
  # state some path enters, its ancestors included, following Appendix D's
  # `addDescendantStatesToEnter` and `addAncestorStatesToEnter`. The root is
  # entered by its default. Entering a state by its default enters its
  # `initial` states as targets (a compound state or the root), every child
  # that is not a history by its default (a parallel state), or its history
  # default transition's targets as targets (a history pseudo-state).
  # Entering a state as a target enters it by its default, enters each of its
  # proper ancestors, and, for each parallel ancestor, enters by its default
  # every child region that holds none of the transition's targets. Every
  # transition of an entered state enters its targets as targets. No `cond`
  # and no `event` is read, so the rule over-counts and never under-counts.
  # A history pseudo-state contributes no descriptor. Descriptors come in
  # `t_index` order (a state's own transitions before its children's, as the
  # compiler numbers them), within one `event` attribute in the order
  # written, and a descriptor equal as a string to one already listed is
  # dropped.
  #
  # Matching is transition selection's own, {Interpreter::NameMatch}.
  #
  # @api private
  module Accepts
    module_function

    # The accepts check of `declared` against `machine`'s vocabulary.
    #
    # @param machine [Machine] a compiled chart
    # @param declared [Array<String>, nil] the declared event names, or nil
    #   for no declaration
    # @return [AcceptsCheck]
    def check(machine, declared)
      return AcceptsCheck.new(unreachable: [].freeze, undeclared: [].freeze) if declared.nil?

      descriptors = tokenized(vocabulary(machine))
      names = tokenized(declared.uniq.map(&:-@))
      AcceptsCheck.new(unreachable: unreachable(names, descriptors), undeclared: undeclared(names, descriptors))
    end

    # Each of `strings` with its tokens, as `[string, tokens]`.
    def tokenized(strings) = strings.map { [_1, Interpreter::NameMatch.tokenize(_1)] }

    # The declared names no descriptor matches, frozen.
    def unreachable(names, descriptors)
      descriptor_tokens = descriptors.map(&:last)
      names.reject { Interpreter::NameMatch.name_match?(descriptor_tokens, _2) }.map(&:first).freeze
    end

    # The descriptors that match no declared name, frozen.
    def undeclared(names, descriptors)
      descriptors.reject { |_, tokens| names.any? { Interpreter::NameMatch.name_match?([tokens], _2) } }
                 .map(&:first).freeze
    end

    # The chart's event vocabulary (the reference's `events/1`): every
    # descriptor on a transition of a state that can be active, history
    # pseudo-states left out, in `t_index` order and without duplicates.
    #
    # @param machine [Machine] a compiled chart
    # @return [Array<String>] frozen descriptors
    def vocabulary(machine)
      entered_states(machine)
        .reject { machine.history?(_1) }
        .flat_map { machine.state(_1).transitions }
        .sort
        .flat_map { |t_index| machine.transitions.fetch(t_index).events.map { -_1.join(".") } }
        .uniq
    end

    # The least set of state indexes closed under the entry rule, as a
    # worklist: `[:default, index]` enters a state by its default and
    # `[:targets, indexes]` enters one transition's (or one `initial`'s)
    # targets as targets. `defaulted` bounds the default expansions and
    # `entered` bounds the per-state transition walk, so each state's work is
    # queued once and the walk ends on any chart, cycles included.
    def entered_states(machine)
      entered = Set.new
      defaulted = Set.new
      work = [[:default, 0]]
      work.concat(entry_work(machine, work.pop, entered, defaulted)) until work.empty?
      entered.to_a
    end

    # The work one entry adds: a state entered by its default (once), or one
    # list of targets entered as targets.
    def entry_work(machine, (kind, subject), entered, defaulted)
      return enter_targets(machine, subject, entered) if kind == :targets
      return [] unless defaulted.add?(subject)

      mark_entered(machine, subject, entered) + default_entry(machine, subject)
    end

    # The work entering `targets` as targets adds: each target by its
    # default, and each proper ancestor entered, with its own transitions'
    # work and, for a parallel ancestor, its untargeted regions by default.
    def enter_targets(machine, targets, entered)
      ancestors = targets.flat_map { machine.proper_ancestors(_1) }.uniq
      ancestor_work = ancestors.flat_map do |ancestor|
        mark_entered(machine, ancestor, entered) + untargeted_regions(machine, ancestor, targets)
      end
      targets.map { [:default, _1] } + ancestor_work
    end

    # What entering `index` by its default enters next, by kind: a parallel
    # state's regions by their defaults, a history's default transition's
    # targets as targets, and otherwise the compiler-resolved `initial` as
    # targets - nothing on an atomic state.
    def default_entry(machine, index)
      state = machine.state(index)
      case state.kind
      when :parallel then machine.child_states(index).map { [:default, _1] }
      when :history
        state.history_default.nil? ? [] : [[:targets, machine.transitions.fetch(state.history_default).targets]]
      else state.initial.empty? ? [] : [[:targets, state.initial]]
      end
    end

    # A parallel ancestor's regions that hold none of `targets`, each to be
    # entered by its default; nothing for any other ancestor.
    def untargeted_regions(machine, ancestor, targets)
      return [] unless machine.parallel?(ancestor)

      machine.child_states(ancestor)
             .reject { |region| targets.any? { _1 == region || machine.descendant?(_1, region) } }
             .map { [:default, _1] }
    end

    # Marks `index` entered. The first time only, answers the work its own
    # transitions add: each targeted transition's targets, as targets.
    def mark_entered(machine, index, entered)
      return [] unless entered.add?(index)

      machine.state(index).transitions
             .map { machine.transitions.fetch(_1).targets }
             .reject(&:empty?)
             .map { [:targets, _1] }
    end
  end
end
