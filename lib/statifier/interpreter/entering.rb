# frozen_string_literal: true

module Statifier
  module Interpreter
    # The pseudocode's three `computeEntrySet` out-parameters, one value:
    # `states_to_enter`; `states_for_default_entry`, the compound states
    # among them entered by default rather than as a target; and
    # `default_history_content`, by a history's parent, the `t_index` of the
    # history's default transition, whose content runs because the history
    # had recorded nothing. The two sets are frozen ascending Arrays and the
    # map a frozen Hash.
    #
    # @api private
    EntrySet = ::Data.define(:states_to_enter, :states_for_default_entry, :default_history_content) do
      # The entry set with `index` added to `states_to_enter`.
      def add(index) = with(states_to_enter: put(states_to_enter, index))

      # The entry set with `index` added to `states_for_default_entry`.
      def flag_default_entry(index) = with(states_for_default_entry: put(states_for_default_entry, index))

      # The entry set with `t_index` registered as `parent`'s default
      # history content.
      def register_history_content(parent, t_index)
        with(default_history_content: default_history_content.merge(parent => t_index).freeze)
      end

      private

      def put(set, index) = set.include?(index) ? set : (set + [index]).sort.freeze
    end

    class EntrySet
      # An entry set with nothing in it.
      EMPTY = new(states_to_enter: [].freeze, states_for_default_entry: [].freeze,
                  default_history_content: {}.freeze)
    end

    # The entry set, ported function for function from the pseudocode as
    # the reference ports it: what a set of transitions enters. Each
    # function threads an {EntrySet} through and answers the one it leaves,
    # where the pseudocode writes into its out-parameters.
    #
    # @api private
    module Entering
      module_function

      # `computeEntrySet`: what `transitions` enter. For each, every written
      # target enters with its descendants, then every effective target (a
      # history resolved to what it stands for) enters its ancestors up to
      # the transition's domain.
      #
      # @return [EntrySet]
      def compute_entry_set(snapshot, transitions)
        transitions.reduce(EntrySet::EMPTY) do |entry_set, transition|
          entry_set = transition.targets.reduce(entry_set) do |set, target|
            add_descendant_states_to_enter(snapshot, target, set)
          end
          domain = Selection.get_transition_domain(snapshot, transition)
          Selection.get_effective_target_states(snapshot, transition).reduce(entry_set) do |set, target|
            add_ancestor_states_to_enter(snapshot, target, domain, set)
          end
        end
      end

      # `addDescendantStatesToEnter`: `index` and what enters with it, added
      # to `entry_set`. A history restores its recorded value or, having
      # recorded nothing, follows its default transition and registers that
      # transition's content on its parent. A compound state is marked as
      # entered by default and enters its initial targets. A parallel enters
      # every region no state already in the set lies inside. Any other state
      # enters alone.
      #
      # @return [EntrySet]
      def add_descendant_states_to_enter(snapshot, index, entry_set)
        machine = snapshot.machine
        return enter_history_target(snapshot, index, entry_set) if machine.history?(index)

        entry_set = entry_set.add(index)
        if machine.compound?(index)
          enter_targets(snapshot, initial_targets(machine, index), index, entry_set.flag_default_entry(index))
        elsif machine.parallel?(index)
          enter_uncovered_regions(snapshot, index, entry_set)
        else
          entry_set
        end
      end

      # `addAncestorStatesToEnter`: every proper ancestor of `index` up to
      # but not including `ancestor` enters, each parallel among them with
      # its regions not yet covered. A nil `ancestor` bounds nothing.
      #
      # @return [EntrySet]
      def add_ancestor_states_to_enter(snapshot, index, ancestor, entry_set)
        machine = snapshot.machine
        machine.proper_ancestors(index).take_while { _1 != ancestor }.reduce(entry_set) do |set, anc|
          set = set.add(anc)
          machine.parallel?(anc) ? enter_uncovered_regions(snapshot, anc, set) : set
        end
      end

      # The history arm: the recorded value when there is one, else the
      # default transition's targets with its content registered on the
      # history's parent; either way the targets enter up to that parent.
      def enter_history_target(snapshot, history_index, entry_set)
        history = snapshot.machine.state(history_index)
        recorded = snapshot.history[history_index]
        return enter_targets(snapshot, recorded, history.parent, entry_set) unless recorded.nil?

        default = history.history_default
        targets = snapshot.machine.transitions.fetch(default).targets
        enter_targets(snapshot, targets, history.parent, entry_set.register_history_content(history.parent, default))
      end

      # Every target's descendants, then every target's ancestors up to
      # `ancestor`.
      def enter_targets(snapshot, targets, ancestor, entry_set)
        entry_set = targets.reduce(entry_set) { |set, target| add_descendant_states_to_enter(snapshot, target, set) }
        targets.reduce(entry_set) { |set, target| add_ancestor_states_to_enter(snapshot, target, ancestor, set) }
      end

      # A compound state's default-entry targets: its `<initial>`
      # transition's when the document wrote one, else the default the
      # compiler resolved from the `initial` attribute or the first child.
      def initial_targets(machine, index)
        t_index = machine.state(index).initial_transition
        t_index.nil? ? machine.state(index).initial : machine.transitions.fetch(t_index).targets
      end

      # Every region of the parallel `index` that no state already in the
      # set lies inside enters with its descendants. A history child is
      # never a region.
      def enter_uncovered_regions(snapshot, index, entry_set)
        machine = snapshot.machine
        machine.child_states(index).reduce(entry_set) do |set, region|
          covered = set.states_to_enter.any? { machine.descendant?(_1, region) }
          covered ? set : add_descendant_states_to_enter(snapshot, region, set)
        end
      end
    end
  end
end
