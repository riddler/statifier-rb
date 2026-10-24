# frozen_string_literal: true

module Statifier
  module Validator
    # The checks of `<donedata>`, `<content>`, `<param>`, `<datamodel>` and
    # `<data>`.
    #
    # @api private
    module DataChecks
      # The rules of one `<data>`, in the reference's order.
      DATA_RULES = {
        data_expr_and_src: ->(data) { !data.expr.nil? && !data.src.nil? },
        data_value_and_children: lambda do |data|
          (!data.expr.nil? || !data.src.nil?) && !Lowering::Reading.blank?(data.text)
        end,
        data_reserved_id: ->(data) { data.id.start_with?("_") }
      }.freeze

      module_function

      # `<donedata>` sits on a `<final>` only, and holds a `<content>` or
      # `<param>` children, not both; each reported at the `<donedata>`.
      def donedata(_document, context)
        carriers = context.states.reject { _1.donedata.nil? }
        both = carriers.select { |state| state.donedata.content && !state.donedata.params.empty? }
        at_donedata(:donedata_not_on_final, carriers.reject { _1.kind == :final }) +
          at_donedata(:donedata_content_and_params, both)
      end

      # The `reason` error of each state, at its `<donedata>`.
      def at_donedata(reason, states) = states.map { Findings.error(reason, _1.donedata.location, id: _1.id) }

      # A `<content>` under `<donedata>` or `<invoke>` does not carry both
      # `expr` and a payload, markup or text that is not blank.
      def contents(_document, context)
        all = context.states.flat_map { [_1.donedata&.content, *_1.invoke.map(&:content)].compact }
        all.filter_map do |content|
          wording = payload(content)
          Findings.error(:content_expr_and_text, content.location, wording:, expr: content.expr) if wording
        end
      end

      # What a `<content>` with `expr` also carries: `"markup"`, `"text"`,
      # or nil.
      def payload(content)
        return if content.expr.nil?
        return "markup" if content.markup

        "text" unless Lowering::Reading.blank?(content.text)
      end

      # A `<param>` under `<donedata>`, `<invoke>` or `<send>` carries exactly
      # one of `expr` and `location`.
      def params(_document, context)
        state_params = context.states.flat_map { [*_1.donedata&.params, *_1.invoke.flat_map(&:params)] }
        (state_params + Executable.sends(context).flat_map(&:params)).filter_map { param_error(_1) }
      end

      # The error of a `<param>` that writes neither or both, or nil.
      def param_error(param)
        written = [param.expr, param.param_location].compact.size
        return if written == 1

        Findings.error(written.zero? ? :param_no_value : :param_expr_and_location, param.location, name: param.name)
      end

      # `<data>`: not both `expr` and `src`, no child text beside either, no
      # id beginning `_`; each at the id's span. Then each `<datamodel>` on a
      # `<final>` or a history.
      def data(document, context)
        datamodels = [document.datamodel_element, *context.states.map(&:datamodel_element)].compact
        datamodels.flat_map(&:data).flat_map { data_errors(_1) } + misplaced_datamodels(context)
      end

      # The errors of one `<data>`.
      def data_errors(data)
        location = States.span(data, :id)
        DATA_RULES.select { |_, broken| broken.call(data) }.keys.map { Findings.error(_1, location, id: data.id) }
      end

      # A `<datamodel>` on a `<final>` or a history.
      def misplaced_datamodels(context)
        context.states.select { %i[final history].include?(_1.kind) && _1.datamodel_element }.map do |state|
          Findings.error(:datamodel_bad_parent, state.datamodel_element.location, kind: state.kind)
        end
      end
    end

    # The checks of the root's namespace and version, and of the enumerated
    # attribute values as written.
    #
    # @api private
    module Enums
      TRANSITION_TYPES = %w[internal external].freeze
      BINDINGS = %w[early late].freeze
      DATAMODELS = %w[predicator elixir null ecmascript xpath].freeze
      AUTOFORWARDS = %w[true false].freeze

      module_function

      # The root resolves to the SCXML namespace (or, for invoke content
      # markup, to none) and its version is `"1.0"`; each reported at the
      # attribute's span, or the root's when it was not written.
      def boilerplate(document, context)
        namespace = document.namespace
        namespace_ok = namespace == Findings::SCXML || (context.invoke_content_markup && namespace.nil?)
        errors = namespace_ok ? [] : [Findings.error(:bad_namespace, States.span(document, :xmlns), uri: namespace)]
        return errors if document.version == "1.0"

        errors + [Findings.error(:bad_version, States.span(document, :version), version: document.version)]
      end

      # Every transition's `type`, the root's `binding` and `datamodel`, and
      # every `<invoke>`'s `autoforward`, as written: lowering maps a value
      # out of range onto the default, so only the text tells them apart.
      def enums(document, context)
        transitions = context.transitions.map(&:first)
        invokes = context.states.flat_map(&:invoke)
        transitions.flat_map { out_of_range(_1, :type, TRANSITION_TYPES, context, :transition_bad_type) } +
          out_of_range(document, :binding, BINDINGS, context, :scxml_bad_binding) +
          out_of_range(document, :datamodel, DATAMODELS, context, :scxml_bad_datamodel) +
          invokes.flat_map { out_of_range(_1, :autoforward, AUTOFORWARDS, context, :invoke_bad_autoforward) }
      end

      # The `reason` error of a written attribute whose raw text is not in
      # `allowed`; an attribute not written is its default, in range.
      def out_of_range(node, key, allowed, context, reason)
        location = node.attribute_locations[key]
        return [] if location.nil?

        raw = location.slice(context.source)
        allowed.include?(raw) ? [] : [Findings.error(reason, location, raw: raw.freeze)]
      end
    end
  end
end
