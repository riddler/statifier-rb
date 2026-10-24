# frozen_string_literal: true

module Statifier
  module Interpreter
    # Transition selection, ported function for function from the
    # pseudocode as the reference ports it; each function names the one it
    # ports.
    #
    # The domain half ({find_lcca}, {get_effective_target_states},
    # {get_transition_domain} and {compute_exit_set}) answers which states a
    # transition leaves; {ExitEntry} uses it too. The selection half
    # ({condition_match}, {select_transitions},
    # {select_eventless_transitions} and {remove_conflicting_transitions})
    # answers which transitions fire.
    #
    # The two selection walks evaluate conditions against one context built
    # per round from the datamodel the caller passes and the snapshot's
    # configuration. A condition that fails, or answers something other than
    # true or false, leaves its transition unselected and raises
    # `error.execution`: the walks answer the raised events with the
    # transitions ({Selected}), in walk order, for the caller to queue.
    #
    # @api private
    module Selection
      # What a selection round answered: `transitions`, the transitions that
      # fire, in the order the round took them; and `raised`, a
      # {Datamodel::ExecutionError} per condition that failed, in walk order,
      # each with the origin `{kind: :transition, t_index:}`.
      Selected = ::Data.define(:transitions, :raised)

      module_function

      # `findLCCA`: the least common compound ancestor of `indexes`
      # ({Machine#lcca}). A parallel is never one.
      def find_lcca(machine, indexes) = machine.lcca(indexes)

      # `getEffectiveTargetStates`: the transition's targets, each history
      # target resolved to its recorded value when it has one, else to its
      # default transition's own effective targets, as a frozen Array. The
      # list is not deduplicated; no caller's answer changes on a repeat.
      def get_effective_target_states(snapshot, transition)
        transition.targets.flat_map { effective_target_states(snapshot, _1) }.freeze
      end

      # One target's effective states.
      def effective_target_states(snapshot, target)
        machine = snapshot.machine
        return [target] unless machine.history?(target)
        return snapshot.history.fetch(target) if snapshot.history.key?(target)

        default = machine.transitions.fetch(machine.state(target).history_default)
        get_effective_target_states(snapshot, default)
      end

      # `getTransitionDomain`: the state whose active descendants the
      # transition exits, or nil when its effective targets are empty. An
      # internal transition whose source is compound and whose every
      # effective target is a proper descendant of it has the source as its
      # domain; any other has the least common compound ancestor of its
      # source and its effective targets.
      def get_transition_domain(snapshot, transition)
        targets = get_effective_target_states(snapshot, transition)
        return nil if targets.empty?

        machine = snapshot.machine
        source = transition.source
        return source if internal_domain?(machine, transition, targets)

        find_lcca(machine, [source, *targets])
      end

      # Whether an internal transition's domain is its own source.
      def internal_domain?(machine, transition, targets)
        source = transition.source
        transition.type == :internal && machine.compound?(source) &&
          targets.all? { machine.descendant?(_1, source) }
      end

      # `computeExitSet`: every active state that is a proper descendant of
      # some transition's domain, across `transitions`, as a frozen Array in
      # document order (exit order is its reverse). A transition with no
      # written target contributes nothing, and neither does one whose
      # written targets resolve to no domain.
      def compute_exit_set(snapshot, transitions)
        exit_set = transitions.reject { _1.targets.empty? }.flat_map do |transition|
          domain = get_transition_domain(snapshot, transition)
          domain.nil? ? [] : snapshot.configuration.select { snapshot.machine.descendant?(_1, domain) }
        end
        exit_set.uniq.sort.freeze
      end

      # `conditionMatch`: the transition's condition evaluated against `data`
      # and the snapshot's configuration (for `In()`); no condition is true.
      #
      # @return [Datamodel::Evaluated] true or false, or the reason it failed
      def condition_match(snapshot, transition, data, clock: nil)
        Datamodel.evaluate_cond(context(snapshot, data, clock), transition.cond)
      end

      # `selectTransitions`: the transitions the event named `name` enables,
      # at most one per active atomic state, the states taken in document
      # order. Each state is searched, then each proper ancestor outward, for
      # the first transition in document order whose descriptors match the
      # name and whose condition holds, so a descendant's transition preempts
      # an ancestor's. The first occurrence of each transition is kept, and
      # the list passes through {remove_conflicting_transitions}.
      #
      # @return [Selected]
      def select_transitions(snapshot, name, data, clock: nil)
        round(snapshot, context(snapshot, data, clock), NameMatch.tokenize(name))
      end

      # `selectEventlessTransitions`: {select_transitions}'s walk over the
      # transitions that name no event. A transition naming one is never
      # taken here, and an eventless one never by {select_transitions}.
      #
      # @return [Selected]
      def select_eventless_transitions(snapshot, data, clock: nil)
        round(snapshot, context(snapshot, data, clock), nil)
      end

      # `removeConflictingTransitions`: the enabled transitions, filtered to
      # a set no two of which exit a common state. Taken in the order given,
      # each is checked against those kept so far: on a conflict, one whose
      # source is a descendant of the kept one's source preempts it and keeps
      # checking; otherwise the later one is dropped and the check stops. A
      # surviving transition is appended after every kept one it preempted is
      # removed.
      def remove_conflicting_transitions(snapshot, enabled)
        enabled.reduce([]) do |filtered, candidate|
          preempted = resolve(snapshot, candidate, filtered)
          preempted.nil? ? filtered : (filtered - preempted) + [candidate]
        end.freeze
      end

      # The kept transitions `candidate` preempts, or nil when a kept one
      # preempts `candidate`.
      def resolve(snapshot, candidate, filtered)
        filtered.each_with_object([]) do |kept, preempted|
          next unless conflict?(snapshot, candidate, kept)
          return nil unless snapshot.machine.descendant?(candidate.source, kept.source)

          preempted << kept
        end
      end

      # Whether two transitions' exit sets share a state.
      def conflict?(snapshot, one, other)
        compute_exit_set(snapshot, [one]).intersect?(compute_exit_set(snapshot, [other]))
      end

      # The round both selection walks share: every active atomic state in
      # document order, the failed conditions raised in walk order, the first
      # occurrence of each transition kept and the conflicts removed.
      # `tokens` is nil for the eventless walk.
      def round(snapshot, context, tokens)
        raised = []
        enabled = snapshot.configuration.select { snapshot.machine.atomic?(_1) }.sort.filter_map do |atomic|
          selected_for_atomic_state(snapshot.machine, context, atomic, tokens, raised)
        end
        transitions = remove_conflicting_transitions(snapshot, enabled.uniq(&:t_index))
        Selected.new(transitions:, raised: raised.freeze)
      end

      # The labelled `break loop` of one atomic state's search: the state,
      # then each proper ancestor outward, stopping at the first that has an
      # enabled transition.
      def selected_for_atomic_state(machine, context, atomic, tokens, raised)
        [atomic, *machine.proper_ancestors(atomic)].each do |index|
          found = first_matching_transition(machine, context, index, tokens, raised)
          return found unless found.nil?
        end
        nil
      end

      # A state's own transitions in document order, stopping at the first
      # enabled one, so a later sibling's condition is never evaluated once
      # an earlier one is taken.
      def first_matching_transition(machine, context, index, tokens, raised)
        machine.state(index).transitions.each do |t_index|
          transition = machine.transitions.fetch(t_index)
          return transition if enabled?(context, transition, tokens, raised)
        end
        nil
      end

      # The eventless predicate when `tokens` is nil, the event-matched one
      # otherwise; both end in the transition's condition, a failure of
      # which is recorded in `raised`.
      def enabled?(context, transition, tokens, raised)
        eventless = transition.events.empty?
        return false unless tokens.nil? ? eventless : !eventless && NameMatch.name_match?(transition.events, tokens)

        evaluated = Datamodel.evaluate_cond(context, transition.cond)
        return evaluated.value if evaluated.ok?

        origin = { kind: :transition, t_index: transition.t_index }
        raised << Datamodel::ExecutionError.new(origin:, reason: evaluated.error)
        false
      end

      # The context one round evaluates against.
      def context(snapshot, data, clock)
        Datamodel.context(data, snapshot.machine, snapshot.configuration, clock:)
      end
    end
  end
end
