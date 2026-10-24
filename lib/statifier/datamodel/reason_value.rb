# frozen_string_literal: true

module Statifier
  module Datamodel
    # A failure as the predicator value its `error.*` event carries as data,
    # so a chart can read `_event.data` and every evaluation that reads
    # `_event` stays a predicator evaluation. The reference carries its
    # failure terms as they are; predicator refuses a context holding a
    # value that is not its own, so here a reason becomes a Hash.
    #
    # @api private
    module ReasonValue
      # The predicator values a reason may carry, kept as they are.
      VALUE_TYPES = [Predicator::Duration, Predicator::Date, Predicator::DateTime].freeze

      module_function

      # `reason` as a predicator value: a reason becomes a Hash of its fields
      # under String keys, with `"kind"` its name in snake case (an
      # `InvalidTarget` is `{"kind" => "invalid_target", "target" => ...}`),
      # applied all the way down; a Symbol becomes its String; a predicator
      # value stays as it is.
      def of(reason)
        case reason
        when ::Data then VALUE_TYPES.include?(reason.class) ? reason : fields(reason)
        when Symbol then reason.to_s
        when Hash then reason.to_h { |key, value| [of(key), of(value)] }
        when Array then reason.map { of(_1) }
        else reason
        end
      end

      # A reason's fields with its kind first.
      def fields(reason)
        { "kind" => kind(reason.class) }.merge(reason.to_h.to_h { |key, value| [key.to_s, of(value)] })
      end

      # A reason class's name in snake case.
      def kind(klass) = klass.name.split("::").last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
