# frozen_string_literal: true

module Statifier
  module Datamodel
    # The `<data>` binding, as the reference binds (the specification's
    # sections 5.3.2 and 5.3.3 and B.2.2; its appendix gives no procedure
    # body).
    #
    # When the chart starts every `<data>` id is created, as undefined, and
    # what binds then binds: every `<data>` under early binding, the root's
    # own under late binding. A root `<data>` whose id the host's datamodel
    # already held keeps the host's value. Under late binding a state's own
    # `<data>` binds when the state is first entered; the caller decides
    # that it is the first entry.
    #
    # One context serves a whole pass, since no `<data>` may read another in
    # the same pass. A value that fails (an `expr` that did not compile, a
    # `src`, which nothing here fetches, or an evaluation that fails) leaves
    # the id undefined and raises an {ExecutionError} whose origin is
    # `{kind: :data, d_index:}`.
    #
    # @api private
    module DataBinding
      # What a binding pass answers: `data`, the datamodel it leaves, and
      # `raised`, the {ExecutionError}s it raised, in `d_index` order.
      Bound = ::Data.define(:data, :raised)

      module_function

      # The binding when the chart starts. `context.data` is the host's
      # datamodel with the system variables seeded.
      #
      # @return [Bound]
      def start(context)
        seeded = context.machine.data_elements.reduce(context.data) do |data, element|
          data.key?(element.id) ? data : data.merge(element.id => Predicator::UNDEFINED)
        end
        bind_all(context.with(data: seeded.freeze), starting_indexes(context.machine, context.data.keys))
      end

      # The `<data>` that bind when the chart starts: every one under early
      # binding, the root's own under late, less the root's whose id the
      # host supplied.
      def starting_indexes(machine, host_ids)
        root_data = machine.state(0).data
        indexes = machine.binding == :early ? machine.data_elements.map(&:d_index) : root_data
        indexes.reject { root_data.include?(_1) && host_ids.include?(machine.data_elements[_1].id) }
      end

      # The binding of `state_index`'s own `<data>` on its first entry:
      # nothing under early binding, and nothing for the root, whose own
      # bound when the chart started (binding it again would overwrite a
      # value the host supplied).
      #
      # @return [Bound]
      def enter_state(context, state_index)
        machine = context.machine
        return Bound.new(data: context.data, raised: []) if machine.binding == :early || state_index.zero?

        bind_all(context, machine.state(state_index).data)
      end

      # Each of `indexes` bound in ascending order against the one context.
      def bind_all(context, indexes)
        data, raised = indexes.sort.reduce([context.data, []]) { |bound, index| bind_one(context, bound, index) }
        Bound.new(data: data.freeze, raised: raised.freeze)
      end

      # The pass so far, `[data, raised]`, with the `<data>` at `d_index`
      # bound, or its `error.execution` raised.
      def bind_one(context, (data, raised), d_index)
        element = context.machine.data_elements[d_index]
        evaluated = value_of(context, element.value)
        return [data.merge(element.id => evaluated.value), raised] if evaluated.ok?

        [data, raised + [ExecutionError.new(origin: { kind: :data, d_index: }, reason: evaluated.error)]]
      end

      # A `<data>` value evaluated; a `src` fails, as nothing here fetches it.
      def value_of(context, value)
        return Evaluated.new(value: nil, error: SrcValue.new(src: value.src)) if value.is_a?(Machine::Src)

        Datamodel.evaluate(context, value)
      end
    end
  end
end
