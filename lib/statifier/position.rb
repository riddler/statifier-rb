# frozen_string_literal: true

require "predicator/tagged"

module Statifier
  # Position export and import: a chart's execution between two calls, in
  # the string-id vocabulary the reference moves a position in and out with
  # (`Statifier.Position.export/1` and `import/2` in statifier-ex), written
  # as plain data a host can keep as JSON. {Statifier.export_position} and
  # {Statifier.import_position} answer through this module.
  #
  # A position is a Hash with String keys, the reference's required export
  # keys in its order ({KEYS}), every value a String, an Integer, a
  # boolean, an Array or a Hash of those:
  #
  # - `configuration`, `entered_states` and `states_to_invoke`: state ids,
  #   sorted, the `<scxml>` root never named;
  # - `history_values`: each history state's id to the ids it recorded,
  #   sorted;
  # - `active_invocations`: one Hash per live invocation, `state` (the id of
  #   the state that owns the `<invoke>`), `invoke_index` (its ordinal
  #   among that state's own) and `invoke_id`, sorted by state and index;
  # - `invoke_counter`, `send_counter` and `timer_counter`: the sequences
  #   behind the generated invoke ids, the generated send ids and the timer
  #   ordinals;
  # - `datamodel`: every variable, the system variables included, by name,
  #   each value as text in predicator's tagged-value encoding
  #   (`Predicator::Tagged`), which carries the dates, durations and the
  #   undefined value JSON has no form for;
  # - `running` and `trace`, booleans; `status`, `"running"` or `"done"`;
  #   the counters `macrostep`, `microstep` and `round`; and
  #   `max_macrostep_rounds`, a positive Integer or `"infinity"`.
  #
  # The reference's export carries the same keys as Elixir terms (sets,
  # tuple keys, atoms) and an `identity`, the chart's content hash, name and
  # version, which its import never reads. A machine here carries no
  # identity, so a position carries none either, and an import loads a
  # position onto any machine that holds every state it names, as the
  # reference's does.
  #
  # Nothing of the driver's own is in a position, as the reference's
  # position holds none of its session's: the virtual clock, the pending
  # timers, the external queue, the sends a processor holds, a budget halt,
  # the stopped chart's donedata and the state's last event selection. An
  # import starts them as a fresh start does: the clock at zero, no timer,
  # nothing queued or held, no halt. The session id is the one the
  # position's `_sessionid` holds, and the registered send types are the
  # processors the host passes the import.
  #
  # A host reads {KEYS} and {Refusal} here; the functions are the bodies of
  # the two calls, and they and the modules beneath are internal.
  module Position
    # The keys a position carries, in the reference's order, every one
    # required by an import.
    KEYS = %w[
      configuration entered_states states_to_invoke history_values active_invocations invoke_counter
      send_counter timer_counter datamodel running status macrostep microstep round trace max_macrostep_rounds
    ].freeze

    # The system variable the session id is read from.
    SESSION_ID = "_sessionid"

    # Why an export or an import was refused, the `error` of its
    # {Statifier::Result}.
    #
    # @!attribute [r] reason
    #   @return [Symbol] `:internal_queue_not_empty`, `:unnameable_states`
    #     or `:unencodable_value` for an export; `:malformed_export` or
    #     `:unknown_state_ids` for an import
    # @!attribute [r] detail
    #   @return [Hash] what the reason names, frozen: `indexes` for
    #     `:unnameable_states`; `field` and the codec's `reason` for
    #     `:unencodable_value`; `ids` for `:unknown_state_ids`; for
    #     `:malformed_export`, a `kind` (`:not_a_hash`, `:missing_keys` with
    #     `keys`, `:bad_shape`, `:undecodable_value` or `:no_session_id`,
    #     each with `field`); empty for `:internal_queue_not_empty`
    Refusal = ::Data.define(:reason, :detail)

    module_function

    # {Statifier.export_position}'s body.
    #
    # @return [Result]
    def export(state)
      machine_state = state.machine_state
      return refused(:internal_queue_not_empty) unless machine_state.internal_queue.empty?

      unnameable = unnameable(machine_state)
      return refused(:unnameable_states, indexes: unnameable) unless unnameable.empty?

      datamodel, failure = Text.encode(machine_state.datamodel)
      return refused(:unencodable_value, **failure) if datamodel.nil?

      ok(exported(machine_state, datamodel))
    end

    # The indexes, sorted, other than the root's, that the state holds and
    # that no id names: a state the document gave no id.
    def unnameable(machine_state)
      machine = machine_state.machine
      referenced(machine_state).reject { _1.zero? || nameable?(machine, _1) }.sort
    end

    # Every state index a position's fields hold, once each.
    def referenced(machine_state)
      history = machine_state.history.flat_map { |key, recorded| [key, *recorded] }
      invoking = machine_state.active_invocations.keys.map(&:first)
      (machine_state.configuration + machine_state.entered_states + machine_state.states_to_invoke + history +
        invoking).uniq
    end

    # Whether the document's id for the state at `index` names it.
    def nameable?(machine, index)
      id = machine.state(index).id
      !id.nil? && machine.id_to_index[id] == index
    end

    # The position, deeply frozen.
    def exported(machine_state, datamodel)
      machine = machine_state.machine
      Ractor.make_shareable(
        { "configuration" => ids(machine, machine_state.configuration),
          "entered_states" => ids(machine, machine_state.entered_states),
          "states_to_invoke" => ids(machine, machine_state.states_to_invoke),
          "history_values" => history(machine, machine_state.history),
          "active_invocations" => invocations(machine, machine_state.active_invocations),
          **counters(machine_state), "datamodel" => datamodel, **flags(machine_state) }
      )
    end

    # The recorded history by id, sorted by the history state's id.
    def history(machine, recorded) = recorded.map { |key, values| [name(machine, key), ids(machine, values)] }.sort.to_h

    # The id of the state at `index`.
    def name(machine, index) = machine.state(index).id

    # The ids of the states at `indexes`, the root left out, sorted.
    def ids(machine, indexes) = (indexes.uniq - [0]).map { name(machine, _1) }.sort

    # The live invocations, sorted by their state's id and their index.
    def invocations(machine, active)
      entries = active.map do |(state_index, invoke_index), invoke_id|
        { "state" => name(machine, state_index), "invoke_index" => invoke_index, "invoke_id" => invoke_id }
      end
      entries.sort_by { [_1["state"], _1["invoke_index"]] }
    end

    # The three sequences, as the position carries them.
    def counters(machine_state)
      { "invoke_counter" => machine_state.invoke_counter, "send_counter" => machine_state.sends.send_counter,
        "timer_counter" => machine_state.sends.timer_counter }
    end

    # The fields after the datamodel, as the position carries them.
    def flags(machine_state)
      budget = machine_state.max_macrostep_rounds
      { "running" => machine_state.running, "status" => machine_state.status.to_s,
        **machine_state.counters.transform_keys(&:to_s), "trace" => machine_state.trace,
        "max_macrostep_rounds" => budget == :infinity ? "infinity" : budget }
    end

    # {Statifier.import_position}'s body: the position checked, its
    # datamodel decoded, every id it names resolved against `machine`, and
    # the state rebuilt.
    #
    # @return [Result]
    def import(machine, position, processors)
      types = Driver::Checks.registered_types(processors)
      failure = Shape.failure(position)
      return refused(:malformed_export, **failure) if failure

      datamodel, failure = Text.decode(position["datamodel"])
      return refused(:malformed_export, **failure) if datamodel.nil?

      unknown = Shape.unknown_ids(machine, position)
      return refused(:unknown_state_ids, ids: unknown) unless unknown.empty?

      ok(Rebuild.state(machine, position, datamodel, types))
    end

    # A successful result.
    def ok(value) = Result.new(value:, error: nil)

    # A refused result, its detail frozen.
    def refused(reason, **detail)
      Result.new(value: nil, error: Refusal.new(reason:, detail: Ractor.make_shareable(detail)))
    end
  end
end

require_relative "position/text"
require_relative "position/shape"
require_relative "position/rebuild"
