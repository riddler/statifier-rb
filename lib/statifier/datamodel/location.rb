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
    # {InvalidLocation}. A bracket key is taken only in the forms the
    # reference's location reader takes (a string literal, an integer
    # literal, a negative integer literal, an identifier); any other key is
    # refused as a {ComputedKey}, as the reference refuses it.
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

        shape_refusal(compiled.value, location) || (compiled.value[0...-2] + [["make_list", compiled.value.last[1]]])
      end

      # The refusal of compiled `location = null` instructions that are not
      # one assignment target, or whose target has a computed key; nil when
      # they are neither.
      def shape_refusal(instructions, location)
        return refused(InvalidLocation.new(location:)) unless one_target?(instructions)

        refused(ComputedKey.new(location:)) unless plain_keys?(instructions[1...-2])
      end

      # Whether `instructions` are one store of null whose root is the first
      # instruction and stays on the stack to the store, so nothing but the
      # target runs.
      def one_target?(instructions)
        return false unless Stores.readable?(instructions)

        depths = Stores.depths(instructions)
        instructions.one? { _1.first == "store" } && instructions.last.first == "store" &&
          instructions[-2] == ["lit", nil] && !Stores.root_name(instructions, 0).nil? &&
          depths[1...-1].all? { _1&.positive? }
      end

      # Whether every segment after the root is one the reference takes as a
      # key: a name or a string literal (one `lit` of a String), an integer
      # literal (one `lit` of an Integer), a negative one (that `lit` and
      # `unary_minus`), or an identifier (one `load`), whose value the write
      # then takes. Any other key is computed, and the reference refuses it.
      def plain_keys?(segments)
        until segments.empty?
          taken = key_size(segments)
          return false if taken.zero?

          segments = segments.drop(taken)
        end
        true
      end

      # How many instructions the key at the head of `segments` takes, 0 when
      # the head is not a key the reference takes.
      def key_size(segments)
        (opcode, operand), following = segments
        case opcode
        when "load" then 1
        when "lit" then lit_key_size(operand, following)
        else 0
        end
      end

      # How many instructions a `lit` of `operand` followed by `following`
      # takes as a key: 2 for a negative integer literal, 1 for a String or
      # an Integer, 0 for any other literal.
      def lit_key_size(operand, following)
        return 0 unless operand.is_a?(String) || operand.is_a?(Integer)

        operand.is_a?(Integer) && following == ["unary_minus"] ? 2 : 1
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
