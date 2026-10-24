# frozen_string_literal: true

module Statifier
  module Position
    # The checks an import makes before it reads a state id, as the
    # reference's import makes them (`check_required_keys/1` and
    # `check_shapes/1` in statifier-ex): every key present, then each
    # field's shape, the first that fails named; then every id resolved.
    #
    # @api private
    module Shape
      # A list of state ids.
      ID_LIST = ->(value) { value.is_a?(Array) && value.all?(String) }

      # One live invocation.
      INVOCATION = lambda do |value|
        value.is_a?(Hash) && value["state"].is_a?(String) && value["invoke_index"].is_a?(Integer) &&
          value["invoke_id"].is_a?(String)
      end

      # A boolean.
      BOOLEAN = ->(value) { [true, false].include?(value) }

      # An integer.
      INTEGER = ->(value) { value.is_a?(Integer) }

      # Each history state's id to the ids it recorded.
      HISTORY = ->(value) { value.is_a?(Hash) && value.all? { |key, ids| key.is_a?(String) && ID_LIST.call(ids) } }

      # Each variable's name to its value's text.
      TEXTS = ->(value) { value.is_a?(Hash) && value.all? { |key, text| key.is_a?(String) && text.is_a?(String) } }

      # Each field's shape, in the order the fields are checked.
      CHECKS = {
        "configuration" => ID_LIST, "entered_states" => ID_LIST, "states_to_invoke" => ID_LIST,
        "history_values" => HISTORY,
        "active_invocations" => ->(value) { value.is_a?(Array) && value.all?(&INVOCATION) },
        "invoke_counter" => INTEGER, "send_counter" => INTEGER, "timer_counter" => INTEGER,
        "datamodel" => TEXTS,
        "running" => BOOLEAN, "status" => ->(value) { %w[running done].include?(value) },
        "macrostep" => INTEGER, "microstep" => INTEGER, "round" => INTEGER, "trace" => BOOLEAN,
        "max_macrostep_rounds" => ->(value) { value == "infinity" || (value.is_a?(Integer) && value.positive?) }
      }.freeze

      module_function

      # What makes `position` malformed, a detail Hash with its `kind`, or
      # nil when it has the shape: not a Hash; required keys missing, every
      # one named, sorted; or the first field of the wrong shape. A key that
      # is not required is not looked at.
      def failure(position)
        return { kind: :not_a_hash } unless position.is_a?(Hash)

        missing = KEYS.reject { position.key?(_1) }.sort
        return { kind: :missing_keys, keys: missing } unless missing.empty?

        field = CHECKS.find { |key, check| !check.call(position[key]) }&.first
        { kind: :bad_shape, field: } if field
      end

      # Every id `position` names that `machine` holds no state for, once
      # each, sorted.
      def unknown_ids(machine, position) = named(position).reject { machine.id_to_index.key?(_1) }.uniq.sort

      # Every state id a position's fields hold.
      def named(position)
        history = position["history_values"].flat_map { |key, ids| [key, *ids] }
        position["configuration"] + position["entered_states"] + position["states_to_invoke"] + history +
          position["active_invocations"].map { _1["state"] }
      end
    end
  end
end
