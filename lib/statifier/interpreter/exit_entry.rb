# frozen_string_literal: true

module Statifier
  module Interpreter
    # Exit and entry, ported function for function from the pseudocode as
    # the reference ports it; each function names the one it ports. Which
    # transitions fire and which states each one leaves is {Selection}'s,
    # and the entry set is {Entering}'s; this module answers, for a set of
    # transitions that fire, what leaving and entering states means: the
    # states to exit in exit order with the history recorded before any of
    # them leaves, and the states to enter in entry order with, for each,
    # the default-entry and history content to run and the completion events
    # its entry raises.
    #
    # It runs no executable content. The pseudocode's `exitStates` and
    # `enterStates` interleave the configuration's moves with content; here
    # {exit_states} and {enter_states} answer the moves as values ({Exit},
    # {Entry}), and the step that calls them runs each state's `<onexit>`,
    # `<onentry>` and transition content, evaluates a final state's
    # `<donedata>` and queues the completion events, state by state, in the
    # order given. No content moves the configuration, so the answers do not
    # depend on what the content does.
    #
    # Exit order is descending index and entry order ascending, which is
    # document order: a descendant leaves before its ancestors and enters
    # after them, and a parallel's regions leave in reverse document order
    # and enter in document order.
    #
    # @api private
    module ExitEntry
      # What {exit_states} answered: `states`, the states to exit in exit
      # order, each to run its `<onexit>` blocks and leave; `history`, the
      # recorded history with every history child of an exiting state
      # recorded from the configuration as it stood before any state left;
      # and `configuration`, the configuration once they have all left.
      Exit = ::Data.define(:states, :history, :configuration)

      # A completion event an entry raises: `name`, `done.state.` and the
      # completed state's id; `final`, the index of the final state whose
      # entry raised it (the event's origin); and `donedata`, true when the
      # event carries that final state's `<donedata>` (the parent's event)
      # and false when it carries no data (a parallel's).
      Completion = ::Data.define(:name, :final, :donedata)

      # One state's entry, as {enter_states} answers it: `index`, the state;
      # `initial_content`, the `t_index` of its `<initial>` transition when
      # it was entered by default and its document wrote one, else nil;
      # `history_content`, the `t_index` of the default transition a history
      # child registered on it, else nil; `completions`, the {Completion}s
      # its entry raises, in the order they are raised; and `stops`, true
      # for a final state whose parent is the root, whose entry ends the
      # execution and raises nothing.
      Arrival = ::Data.define(:index, :initial_content, :history_content, :completions, :stops)

      # What {enter_states} answered: `states`, an {Arrival} per state to
      # enter in entry order, each to join the configuration and run, in
      # order, its `<onentry>` blocks, its initial content, its history
      # content and then its completions; and `configuration`, the
      # configuration once they have all entered.
      Entry = ::Data.define(:states, :configuration)

      module_function

      # `exitStates`, its moves: the exit set ({Selection.compute_exit_set})
      # in exit order, and the history recorded over it.
      #
      # @return [Exit]
      def exit_states(snapshot, transitions)
        exit_set = Selection.compute_exit_set(snapshot, transitions)
        states = exit_set.reverse.freeze
        Exit.new(states:, history: record_history_values(snapshot, states),
                 configuration: (snapshot.configuration - exit_set).freeze)
      end

      # `exitStates`' history-recording loop: for every history child of
      # every state in `states_to_exit`, in that order, its value, each
      # overwriting what the history had recorded. A shallow history records
      # the state's active children, a deep one its active atomic
      # descendants, both read from the snapshot's configuration.
      def record_history_values(snapshot, states_to_exit)
        machine = snapshot.machine
        recorded = states_to_exit.each_with_object(snapshot.history.dup) do |index, history|
          machine.state(index).history_children.each { history[_1] = recorded_value(snapshot, index, _1) }
        end
        recorded.freeze
      end

      # The value one history child `history_index` of `index` records.
      def recorded_value(snapshot, index, history_index)
        machine = snapshot.machine
        deep = machine.state(history_index).history_type == :deep
        snapshot.configuration.select do |active|
          deep ? machine.atomic?(active) && machine.descendant?(active, index) : machine.state(active).parent == index
        end.freeze
      end

      # `enterStates`, its moves: the entry set
      # ({Entering.compute_entry_set}) in entry order, each state with the
      # content its entry runs and the completion events it raises, read
      # against the configuration as the states before it have joined it.
      # `snapshot` is the one the exit left: its configuration and history
      # after {exit_states}.
      #
      # @return [Entry]
      def enter_states(snapshot, transitions)
        entry_set = Entering.compute_entry_set(snapshot, transitions)
        arrivals = []
        configuration = entry_set.states_to_enter.reduce(snapshot.configuration) do |config, index|
          entered = snapshot.with(configuration: (config | [index]).sort.freeze)
          arrivals << arrival(entered, index, entry_set)
          entered.configuration
        end
        Entry.new(states: arrivals.freeze, configuration:)
      end

      # One state's entry, read with `index` in the configuration.
      def arrival(snapshot, index, entry_set)
        machine = snapshot.machine
        default_entry = entry_set.states_for_default_entry.include?(index)
        stops = machine.final?(index) && machine.state(index).parent.zero?
        Arrival.new(index:, initial_content: default_entry ? machine.state(index).initial_transition : nil,
                    history_content: entry_set.default_history_content[index],
                    completions: stops ? [].freeze : completion_events(snapshot, index), stops:)
      end

      # A final state's completion events: `done.state.` and its parent's
      # id, carrying its `<donedata>`, then, when the parent's own parent is
      # a parallel every region of which is now in a final state,
      # `done.state.` and that parallel's id, carrying no data. A parent with
      # no id raises nothing, its parallel's event included; a parallel with
      # no id raises nothing for itself.
      def completion_events(snapshot, index)
        machine = snapshot.machine
        return [].freeze unless machine.final?(index)

        parent = machine.state(index).parent
        return [].freeze unless named?(machine, parent)

        parent_event = Completion.new(name: "done.state.#{machine.state(parent).id}", final: index, donedata: true)
        [parent_event, *parallel_completion(snapshot, index, machine.state(parent).parent)].freeze
      end

      # The parallel's event, when `grandparent` is a parallel with an id
      # every region of which is in a final state.
      def parallel_completion(snapshot, index, grandparent)
        machine = snapshot.machine
        return [] unless !grandparent.nil? && machine.parallel?(grandparent) && named?(machine, grandparent)
        return [] unless machine.child_states(grandparent).all? { in_final_state?(snapshot, _1) }

        [Completion.new(name: "done.state.#{machine.state(grandparent).id}", final: index, donedata: false)]
      end

      # Whether the state has a non-empty id.
      def named?(machine, index)
        id = machine.state(index).id
        !id.nil? && !id.empty?
      end

      # `isInFinalState`: a compound state is in a final state when an
      # active child is a final; a parallel when every region is,
      # recursively. Anything else, a final itself included, is not.
      def in_final_state?(snapshot, index)
        machine = snapshot.machine
        if machine.compound?(index)
          machine.child_states(index).any? { snapshot.active?(_1) && machine.final?(_1) }
        elsif machine.parallel?(index)
          machine.child_states(index).all? { in_final_state?(snapshot, _1) }
        else
          false
        end
      end
    end
  end
end
