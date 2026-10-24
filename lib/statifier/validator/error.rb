# frozen_string_literal: true

module Statifier
  module Validator
    # Why a chart does not validate: a reason symbol, the detail that reason
    # carries (a frozen Hash), a message for a person, and the span reported.
    # The shape of {Lowering::Error}. An error gates compilation: a chart
    # with one is not compiled.
    #
    # The reasons and their detail, each the reference's:
    #
    # - ids: `:duplicate_id` (`id`), `:empty_id`;
    # - targets: `:unresolved_target` (`id`), `:unresolved_initial` (`id`),
    #   `:initial_not_descendant` (`id`, `parent_id`),
    #   `:initial_on_atomic_state` (`id`);
    # - default transitions: `:initial_attribute_and_element` (`id`),
    #   `:transition_count` (`owner`, `count`), `:transition_missing_target`
    #   (`owner`), `:transition_forbidden_attribute` (`owner`, `attribute`,
    #   `:event` or `:cond`); an `owner` is a frozen Hash, `kind` (`:initial`
    #   or `:history`) and `id`, the owning state's id;
    # - history and final: `:history_bad_parent` (`id`, `parent_kind`),
    #   `:history_bad_type` (`raw`), `:final_has_states` (`id`),
    #   `:final_has_transitions` (`id`), `:final_parent_missing_id`
    #   (`final_id`), `:default_entry_not_enterable` (`id`, `child_kind`);
    # - enumerated values, read as written: `:transition_bad_type`,
    #   `:scxml_bad_binding`, `:scxml_bad_datamodel`,
    #   `:invoke_bad_autoforward` (each `raw`);
    # - the root: `:bad_namespace` (`uri`), `:bad_version` (`version`);
    # - data: `:donedata_not_on_final` (`id`), `:donedata_content_and_params`
    #   (`id`), `:content_expr_and_text` (`expr`), `:param_expr_and_location`
    #   (`name`), `:param_no_value` (`name`), `:data_expr_and_src` (`id`),
    #   `:data_value_and_children` (`id`), `:data_reserved_id` (`id`),
    #   `:datamodel_bad_parent` (`kind`);
    # - executable content: `:assign_expr_and_text` (`expr`),
    #   `:if_elseif_after_else`, `:if_duplicate_else`,
    #   `:script_no_src_or_text`, `:invoke_type_and_typeexpr`,
    #   `:invoke_src_and_srcexpr`, `:invoke_src_and_content`,
    #   `:invoke_id_and_idlocation`, `:invoke_namelist_and_param`,
    #   `:send_event_and_eventexpr`, `:send_target_and_targetexpr`,
    #   `:send_type_and_typeexpr`, `:send_id_and_idlocation`,
    #   `:send_delay_and_delayexpr`, `:send_delay_and_internal_target`,
    #   `:send_namelist_and_content`, `:send_param_and_content`,
    #   `:cancel_sendid_and_sendidexpr`, `:cancel_no_sendid`;
    # - the markup: `:duplicate_attribute` (`element`, `attribute`).
    #
    # A reason listed without detail carries an empty Hash.
    #
    # @api private
    Error = ::Data.define(:reason, :detail, :message, :location)

    # A finding that does not gate compilation: the chart is compiled either
    # way, and the engine has a behavior for it. The shape of {Error}. The
    # one reason is `:finalize_forbidden_content` (`element`, `"raise"` or
    # `"send"`): an element the specification forbids inside `<finalize>`.
    #
    # @api private
    Warning = ::Data.define(:reason, :detail, :message, :location)

    # The constructors of {Error} and {Warning}, with the reference's
    # messages.
    #
    # @api private
    module Findings
      SCXML = Lowering::SCXML_NAMESPACE

      module_function

      # @return [Error] the error `reason` with `detail`, at `location`;
      #   `wording` reaches the message and is not kept in the detail
      def error(reason, location, wording: nil, **detail)
        make(Error, Messages::ERROR, [reason, location, wording], detail)
      end

      # @return [Warning] the warning `reason` with `detail`, at `location`
      def warning(reason, location, **detail) = make(Warning, Messages::WARNING, [reason, location, nil], detail)

      # A finding with its detail and message frozen.
      def make(type, messages, (reason, location, wording), detail)
        frozen = detail.transform_values { _1.is_a?(Hash) ? _1.dup.freeze : _1 }.freeze
        message = messages.fetch(reason).call(wording.nil? ? frozen : frozen.merge(wording:))
        type.new(reason:, detail: frozen, message: message.freeze, location:)
      end

      # A value as the reference inspects it: a string quoted, nil as `nil`.
      def inspect_value(value) = value.nil? ? "nil" : Lowering::Errors.quote(value)
    end
  end
end

require_relative "messages"
