# frozen_string_literal: true

module Statifier
  module Interpreter
    # `<foreach>`, as the reference's foreach node runs it
    # (`Statifier.Machine.Content.Foreach` in statifier-ex), for
    # {Content}'s block runner: the names are checked before anything else,
    # and a failure there, or of `array`, keeps nothing.
    #
    # @api private
    module Foreach
      # A `<foreach>` `item` that is not a bare variable name.
      IllegalItemName = ::Data.define(:name)

      # A `<foreach>` `index` that is not a bare variable name.
      IllegalIndexName = ::Data.define(:name)

      # A `<foreach>` `array` that evaluated to something other than a list.
      NotIterable = ::Data.define(:value)

      # A bare variable name, the one shape a `<foreach>` `item` and `index`
      # take.
      NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

      module_function

      # `<foreach>`: the names checked, `array` evaluated once (the list is
      # a value, so the body cannot change what is iterated), the item and
      # index declared undefined when the datamodel does not hold them, and
      # the body run once per element with the item and the zero-based index
      # bound. Unlike an `<assign>`, it may bind a name the datamodel does not
      # yet hold. A body failure keeps what earlier iterations wrote.
      def execute(run, node, stamp)
        collection = iterated(run.context, node)
        return [run, collection] unless collection.is_a?(Array)

        collection.each_with_index.reduce([run.with(context: declare(run.context, node)), nil]) do |(at, _), (value, i)|
          after, reason = Content.nested(at.with(context: bind_iteration(at.context, node, value, i)), node.content,
                                         stamp)
          break [after, reason] unless reason.nil?

          [after, nil]
        end
      end

      # The context with one iteration's item and index bound.
      def bind_iteration(context, node, value, position)
        context = context.bind(node.item, value)
        node.index.nil? ? context : context.bind(node.index, position)
      end

      # The list a `<foreach>` iterates, or the reason it cannot: an illegal
      # item, then an illegal index, then a failed `array`, then a value that
      # is not a list.
      def iterated(context, node)
        illegal = illegal_name(node.item, IllegalItemName) || (node.index && illegal_name(node.index, IllegalIndexName))
        return illegal if illegal

        evaluated = Datamodel.evaluate(context, node.array)
        return evaluated.error unless evaluated.ok?

        evaluated.value.is_a?(Array) ? evaluated.value : NotIterable.new(value: evaluated.value)
      end

      # Why `name` cannot be bound, or nil: a system variable's root, or not a
      # bare name.
      def illegal_name(name, illegal)
        return Datamodel::SystemVariable.new(root: name) if name.start_with?("_")

        NAME.match?(name) ? nil : illegal.new(name:)
      end

      # The context with the item and the index (when written) each declared
      # undefined unless the datamodel holds it, so both are bound even when
      # the list is empty.
      def declare(context, node)
        [node.item, node.index].compact.reduce(context) do |declared, name|
          declared.data.key?(name) ? declared : declared.bind(name, Predicator::UNDEFINED)
        end
      end
    end
  end
end
