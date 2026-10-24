# frozen_string_literal: true

module Statifier
  module Datamodel
    # Reads the stores of a compiled statement program and rewrites them,
    # the mechanism {Program} uses to give a `<script>` the reference's
    # outcome on a published predicator that offers no protected roots and
    # answers no context for a run that stops.
    #
    # The instruction list is predicator's public, versioned shape (the
    # instruction set `Predicator.isa_version` names). A `store n` pops a
    # value and a path of `n` segments, and the path's first segment, its
    # root, is pushed by a `lit` of the root's name, since an assignment's
    # target begins with a name. The stack depth before every instruction is
    # computed by following every jump, so the instruction that pushed a
    # store's root is the last one before the store at the depth the root
    # sits at: everything between keeps the root on the stack.
    #
    # @api private
    module Stores
      # The host function a store into a protected root becomes: it refuses,
      # so the run stops at the attempt. No source can call it: a name in
      # source never holds a colon.
      GUARD = "statifier:protected"

      # The host function each other store reports its root's new value to.
      NOTE = "statifier:wrote"

      # The host function a reachable store whose root cannot be read
      # becomes: it refuses, so such a store never writes unguarded. None of
      # predicator's compiled programs has one.
      UNREAD = "statifier:unread"

      # The jumps, and whether each counts backward.
      JUMPS = { "jump" => false, "pop_jump_if_falsy" => false, "jump_if_falsy_or_pop" => false,
                "jump_if_true_or_pop" => false, "jump_backward" => true }.freeze

      # The stack effect of each instruction whose effect is fixed; one not
      # listed leaves the depth as it is.
      EFFECTS = {
        "lit" => 1, "load" => 1, "object_new" => 1, "duration" => 1, "pop" => -1,
        "compare" => -1, "add" => -1, "subtract" => -1, "multiply" => -1, "divide" => -1, "modulo" => -1,
        "bracket_access" => -1, "in" => -1, "contains" => -1, "object_set" => -1
      }.freeze

      module_function

      # `instructions` with every store into one of `protected_roots` made a
      # call of {GUARD} with its root, a store whose root cannot be read a
      # call of {UNREAD}, and every other store followed by a call of {NOTE}
      # with its root's name and value; every jump moved so it lands where it
      # landed before.
      def guarded(instructions, protected_roots)
        roots = roots(instructions)
        pieces = instructions.each_with_index.map { |instruction, at| piece(instruction, at, roots, protected_roots) }
        starts = pieces.each_with_object([0]) { |piece, acc| acc << (acc.last + piece.size) }
        pieces.each_with_index.flat_map { |piece, at| relocated(piece, at, starts) }
      end

      # The root each reachable store writes, by the store's index: the
      # name, or nil for a store whose root is not a named `lit` (none of
      # predicator's compiled programs has one).
      def roots(instructions)
        depths = depths(instructions)
        instructions.each_with_index.filter_map do |(opcode, count), at|
          next unless opcode == "store" && depths[at]

          [at, root_name(instructions, pusher(depths, at, depths[at] - count - 1))]
        end.to_h
      end

      # The last instruction before `at` that a path reaches at `depth` or
      # below: the one that pushed the slot at `depth`.
      def pusher(depths, at, depth) = (at - 1).downto(0).find { depths[_1] && depths[_1] <= depth }

      # The name the `lit` at `at` pushes, or nil.
      def root_name(instructions, at)
        opcode, name = at && instructions[at]
        name if opcode == "lit" && name.is_a?(String)
      end

      # The stack depth before each instruction, nil for one no path reaches.
      def depths(instructions)
        depths = Array.new(instructions.size)
        pending = [[0, 0]]
        until pending.empty?
          at, depth = pending.pop
          next if at.negative? || at >= instructions.size || depths[at]

          depths[at] = depth
          pending.concat(successors(instructions[at], at, depth))
        end
        depths
      end

      # Where control goes after the instruction at `at`, each with the depth
      # it arrives at.
      def successors((opcode, operand, count), at, depth)
        case opcode
        when "jump" then [[at + operand, depth]]
        when "jump_backward" then [[at - operand, depth]]
        when "pop_jump_if_falsy" then [[at + 1, depth - 1], [at + operand, depth - 1]]
        when "jump_if_falsy_or_pop", "jump_if_true_or_pop" then [[at + 1, depth - 1], [at + operand, depth]]
        else [[at + 1, depth + effect(opcode, operand, count)]]
        end
      end

      # How an instruction moves the depth.
      def effect(opcode, operand, count)
        case opcode
        when "make_list" then 1 - operand
        when "call" then 1 - count
        when "store" then -1 - operand
        else EFFECTS.fetch(opcode, 0)
        end
      end

      # What the instruction at `at` becomes, `roots` the stores read.
      def piece(instruction, at, roots, protected_roots)
        return [instruction] unless roots.key?(at)

        root = roots[at]
        return [["call", UNREAD, 0]] if root.nil?
        return [["lit", root], ["call", GUARD, 1]] if protected_roots.include?(root)

        [instruction, ["lit", root], ["load", root], ["call", NOTE, 2], ["pop"]]
      end

      # A piece with its jump moved to the new index of its old target; a
      # target past the end stays past the end.
      def relocated(piece, at, starts)
        opcode, offset = piece.first
        return piece unless JUMPS.key?(opcode)

        backward = JUMPS.fetch(opcode)
        target = (backward ? at - offset : at + offset).clamp(0, starts.size - 1)
        [[opcode, backward ? starts[at] - starts[target] : starts[target] - starts[at]]]
      end
    end
  end
end
