# frozen_string_literal: true

module Statifier
  module Datamodel
    # A `<script>` program's run, with the reference's outcome.
    #
    # The reference runs a program with every underscore-prefixed root the
    # datamodel already holds protected: a store into one fails at the
    # attempt, so no later statement runs and none reads the value. The
    # writes made before a failure (that one or any other) are kept. A
    # system root the program creates fresh is not on that list; its write
    # lands, the run goes on, and the change found after the run is never
    # kept and fails the run, naming the first such root in sort order.
    #
    # The published predicator offers no protected roots and answers no
    # context for a run that stops, so the program runs rewritten
    # ({Stores.guarded}): a store into a protected root becomes a call of a
    # host function that refuses, which stops the run at that statement as
    # the reference's refusal does; every other store reports its root's
    # new value to a host function that records it, so the writes made
    # before any stop are known. Both host functions live only for the run,
    # and the datamodel the run leaves is the one it started with plus the
    # recorded roots that are not system roots: exactly the roots the
    # reference finds changed, with the same values. A store whose root the
    # rewrite cannot read fails the run rather than write unguarded.
    #
    # Each noted store hands the host function a copy of its root's whole
    # value, so a loop that grows one root costs more per store than the
    # reference's store does; the loop budget bounds it.
    #
    # @api private
    module Program
      # What a host function raises to stop a run at a protected store.
      class Refused < StandardError; end

      module_function

      # Runs `program` (a {Machine::Program}) against `context`.
      #
      # @return [Executed] the datamodel the run leaves and the reason it
      #   failed, if it did: {SystemVariable} for a system root written,
      #   else {EvaluatorError} for predicator's refusal
      def run(context, program)
        before = context.data
        halted = []
        written = {}
        protected_roots = before.keys.select { Datamodel.system_root?(_1) }
        result = Predicator.execute(Stores.guarded(program.instructions, protected_roots), before,
                                    **context.options, functions: functions(context, halted, written))
        outcome(before, written, failure(program, result, halted.first))
      end

      # The context's functions and the run's two: {Stores::GUARD} records
      # the root it refuses in `halted`, {Stores::NOTE} each root's latest
      # value in `written`.
      def functions(context, halted, written)
        context.options[:functions].merge(
          Stores::GUARD => ->(root) { raise Refused, halted.push(root).first },
          Stores::NOTE => ->(root, value) { written.store(root, value).then { nil } },
          Stores::UNREAD => -> { raise Refused, "a store whose root cannot be read" }
        )
      end

      # The reason a run stopped, or nil: a protected root's refusal names
      # its root; any other failure is predicator's.
      def failure(program, result, halted)
        return SystemVariable.new(root: halted) if halted
        return nil if result.ok?

        EvaluatorError.new(source: program.source, error: result.error)
      end

      # The datamodel the run leaves and its failure: a system root the run
      # created fails it when nothing else did.
      def outcome(before, written, failure)
        system, other = written.partition { |root, _value| Datamodel.system_root?(root) }
        failure ||= SystemVariable.new(root: system.map(&:first).min) unless system.empty?
        Executed.new(data: before.merge(other.to_h).freeze, error: failure)
      end
    end
  end
end
