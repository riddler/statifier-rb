# frozen_string_literal: true

module Statifier
  module Position
    # A driver state rebuilt from a checked position, as the reference's
    # `import/2` rebuilds its machine state: every id resolved to its index,
    # the root re-added, the internal queue empty, and the fields a driver
    # declares (the send types and the routes) stamped afresh.
    #
    # @api private
    module Rebuild
      module_function

      # The driver state over `machine` the position holds, `datamodel` its
      # decoded variables and `types` the registered send types.
      #
      # @return [Driver::State]
      def state(machine, position, datamodel, types)
        session_id = datamodel[SESSION_ID]
        machine_state = machine_state(machine, position, datamodel, types, session_id)
        Driver::State.new(machine_state:, session_id:, now_ms: 0, timers: [].freeze, timer_sequence: 0,
                          external_queue: [].freeze, held_sends: {}.freeze, halted: nil, done: done(machine_state),
                          send_types: types, invocations: {}.freeze, mailbox: [].freeze, invoked_as: nil,
                          cancelled: false)
      end

      # The interpreter's position. The root is active whenever any state
      # is, and has been entered whenever any state has.
      def machine_state(machine, position, datamodel, types, session_id)
        configuration = indexes(machine, position["configuration"])
        Interpreter::MachineState.new(
          machine:, configuration: rooted(configuration), history: history(machine, position["history_values"]),
          datamodel:, internal_queue: [].freeze, entered_states: rooted(indexes(machine, position["entered_states"])),
          states_to_invoke: indexes(machine, position["states_to_invoke"]), sends: sends(position, types, session_id),
          caller_context: nil, clock: nil, last_selection: nil, **fields(position),
          active_invocations: invocations(machine, position["active_invocations"])
        )
      end

      # The indexes of the states `ids` name, ascending, frozen.
      def indexes(machine, ids) = ids.map { machine.id_to_index.fetch(_1) }.uniq.sort.freeze

      # `indexes` with the root, when they hold any state.
      def rooted(indexes) = indexes.empty? ? indexes : ([0] | indexes).sort.freeze

      # The recorded history by index.
      def history(machine, values)
        values.to_h { |key, ids| [machine.id_to_index.fetch(key), indexes(machine, ids)] }.freeze
      end

      # The live invocations by state index and invoke index.
      def invocations(machine, entries)
        entries.to_h { [[machine.id_to_index.fetch(_1["state"]), _1["invoke_index"]].freeze, -_1["invoke_id"]] }.freeze
      end

      # The send state: the position's two sequences, and the types and
      # routes a driver declares as a chart starts.
      def sends(position, types, session_id)
        Interpreter::Send::SendState.new(
          send_counter: position["send_counter"], timer_counter: position["timer_counter"],
          send_types: (types unless types.empty?), routes: Driver::Calls.own_routes(session_id)
        )
      end

      # The scalar fields, as the machine state holds them.
      def fields(position)
        budget = position["max_macrostep_rounds"]
        { running: position["running"], status: position["status"].to_sym, macrostep: position["macrostep"],
          microstep: position["microstep"], round: position["round"], trace: position["trace"],
          max_macrostep_rounds: budget == "infinity" ? :infinity : budget, invoke_counter: position["invoke_counter"] }
      end

      # The driver's record of a stopped chart: a stopped position carries
      # no donedata (the reference's carries it only in the done effect), so
      # it is undefined, and the configuration is the position's own.
      def done(machine_state)
        return nil unless machine_state.status == :done

        Effect::Done.new(donedata: Predicator::UNDEFINED, donedata_error: nil,
                         configuration: machine_state.configuration, **machine_state.counters)
      end
    end
  end
end
