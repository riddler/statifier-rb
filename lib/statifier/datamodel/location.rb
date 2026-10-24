# frozen_string_literal: true

module Statifier
  module Datamodel
    # A write of a value at a location, as an `<assign>` makes one, in the
    # reference's order: the location resolves to a path; a root that begins
    # with an underscore is refused; a root the datamodel does not hold is
    # refused; the value the path holds is read; then the value is written
    # at the path. A write never declares a root, and creates only what lies
    # between the root and the leaf, as predicator's store does.
    #
    # The published predicator has no location surface of its own, so the
    # location is read through its compiler: the text compiled as the
    # program `location = null` is one assignment whose target segments are
    # the instructions between the root's `lit` and the value's. Text that
    # is not exactly one assignment target is refused as an
    # {InvalidLocation}.
    #
    # @api private
    module Location
      module_function

      # Writes `value` at `location` (its text) in `context`'s datamodel.
      #
      # @return [Written] the context with the written root bound, the path
      #   and the value it held before, or the reason the write was refused
      def write(context, location, value)
        target = target(location)
        return target if target.is_a?(Written)

        resolved = Predicator.evaluate(target, context.data, **context.options)
        return refused(EvaluatorError.new(source: location, error: resolved.error)) unless resolved.ok?

        checked(context, location, resolved.value, value)
      end

      # The instructions that push the location's path as one list, or the
      # refusal of text that is not one assignment target.
      def target(location)
        compiled = Predicator.compile_program("#{location} = null")
        return refused(EvaluatorError.new(source: location, error: compiled.error)) unless compiled.ok?

        instructions = compiled.value
        return refused(InvalidLocation.new(location:)) unless one_target?(instructions)

        instructions[0...-2] + [["make_list", instructions.last[1]]]
      end

      # Whether `instructions` are one store of null whose root is the first
      # instruction and stays on the stack to the store, so nothing but the
      # target runs.
      def one_target?(instructions)
        depths = Stores.depths(instructions)
        instructions.one? { _1.first == "store" } && instructions.last.first == "store" &&
          instructions[-2] == ["lit", nil] && !Stores.root_name(instructions, 0).nil? &&
          depths[1...-1].all? { _1&.positive? }
      end

      # The write of `value` at `path`, after the reference's two root checks.
      def checked(context, location, path, value)
        root = path.first
        return refused(SystemVariable.new(root:)) if Datamodel.system_root?(root)
        return refused(UnboundLocation.new(location:)) unless context.data.key?(root)

        stored(context, location, path, value)
      end

      # The write itself: `value` stored at `path` in the root's value, as
      # predicator's store writes it, or predicator's refusal.
      def stored(context, location, path, value)
        root = path.first
        result = Predicator.execute(store_of(path, value), { root => context.data[root] })
        return refused(EvaluatorError.new(source: location, error: result.error)) unless result.ok?

        Written.new(context: context.bind(root, result.value[root]), path: path.freeze,
                    prior_value: read(context.data, path), error: nil)
      end

      # The instructions that store `value` at `path`.
      def store_of(path, value) = path.map { ["lit", _1] } + [["lit", value], ["store", path.size]]

      # The value at `path` before the write: a String key against a map, an
      # Integer index against a list (a negative one from the end, as the
      # reference reads it), and undefined on any miss or any step through
      # something else.
      def read(data, path)
        path.reduce(data) do |container, segment|
          case [container, segment]
          in [Hash, String] | [Array, Integer] then container.fetch(segment) { return Predicator::UNDEFINED }
          else return Predicator::UNDEFINED
          end
        end
      end

      # A refused write.
      def refused(reason) = Written.new(context: nil, path: nil, prior_value: nil, error: reason)
    end
  end
end
