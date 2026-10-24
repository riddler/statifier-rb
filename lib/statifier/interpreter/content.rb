# frozen_string_literal: true

module Statifier
  module Interpreter
    # The block runner and the content nodes it runs, as the reference runs
    # them (`Statifier.Interpreter.Content` and `Statifier.Machine.Content.*`
    # in statifier-ex): the specification's `executeContent`.
    #
    # A block runs its nodes in document order against one
    # {Datamodel::Context}: every write a node makes (an `<assign>`, a
    # `<foreach>`'s item and index, a `<script>`'s program, a `<send>`'s
    # `idlocation`) is seen by every node after it. The first node that
    # fails stops the block. The nodes that ran before it keep what they did;
    # the failing node answers no effect, and its failure becomes one
    # `error.*` platform event whose origin is that node, the top-level node
    # of this block when the failure was inside an `<if>` or a `<foreach>`
    # ({NestedContent} then names the inner node). Other blocks are not
    # affected: each call is independent.
    #
    # What a failing node keeps is the reference's: a leaf that fails (a
    # `<log>`, an `<assign>`, a `<cancel>`, a `<send>` whose argument
    # failed, a `<script>` that never compiled) keeps nothing; an `<if>` or
    # a `<foreach>` keeps what its nodes wrote and raised, though not their
    # effects; a `<script>` keeps the writes its program made before it
    # stopped; a refused `<send>` keeps its minted id and its `idlocation`
    # write.
    #
    # A condition of an `<if>` that fails, or answers something other than
    # true or false, does not stop the block: its branch counts as not
    # taken, and its `error.execution` is raised once the top-level node that
    # holds it finishes, after any event the taken branch raised, the order
    # the reference takes.
    #
    # Nothing here moves a queue. The runner answers the events the block
    # raised, in the order they join the internal queue, beside its effects,
    # and the step that called it queues them and stamps their counters.
    #
    # @api private
    module Content
      # Where a block runs: `owner`, the block (`{kind: :onentry,
      # state_index:, ordinal:}`, `{kind: :onexit, state_index:, ordinal:}`,
      # `{kind: :transition, t_index:}` or `{kind: :finalize, state_index:,
      # invoke_index:}`); the counters as they stand while it runs, which no
      # node moves; and `caller_context`, the opaque value the host attached
      # to the step (any object, never copied or frozen here), nil for none.
      Stamp = ::Data.define(:owner, :macrostep, :microstep, :round, :caller_context) do
        # The fields every effect content makes carries: the owner and the
        # counters.
        def fields = { owner:, macrostep:, microstep:, round: }

        # The origin of an event the content node at `c_index` raises.
        def origin(c_index) = { kind: :content, c_index:, owner: }

        # The {Event::Cause} of an event the content node at `c_index`
        # raises: its origin and the counters.
        def cause(c_index) = Event::Cause.new(origin: origin(c_index), macrostep:, microstep:, round:)
      end

      # What a block answered: the `context` it leaves; `sends`, the
      # {Send::SendState} it leaves; `effects` in the order the nodes made
      # them; `raised`, the {Event}s it raised in queue order (an internal
      # event per `<raise>`, a platform `error.execution` per failure and an
      # `error.execution` or `error.communication` per refused `<send>`,
      # each with its {Event::Cause}); and `executed`, the `c_index` of every
      # top-level node that ran, the failing one included.
      Outcome = ::Data.define(:context, :sends, :effects, :raised, :executed)

      # A node inside an `<if>` or a `<foreach>` failed: `c_index` names it
      # and `reason` is its failure.
      NestedContent = ::Data.define(:c_index, :reason)

      # What a block threads from node to node.
      Run = ::Data.define(:context, :sends, :effects, :raised, :pending) do
        # The run with `effect` appended, as a deeply frozen copy
        # ({Effect.frozen_copy}).
        def effect(effect) = with(effects: (effects + [Effect.frozen_copy(effect)]).freeze)

        # The run with `events` raised, each a deeply frozen copy.
        def raise_events(*events) = with(raised: (raised + events.map { Effect.frozen_copy(_1) }).freeze)

        # The run with a condition's failure recorded.
        def defer(reason) = with(pending: (pending + [reason]).freeze)
      end

      module_function

      # The function each kind of node runs through.
      RUNNERS = {
        Machine::Raise => :raise_event, Machine::Log => :log, Machine::Assign => :assign, Machine::If => :if_node,
        Machine::Foreach => :foreach, Machine::Script => :script, Machine::Send => :send_node,
        Machine::Cancel => :cancel
      }.freeze

      # Runs `content`, a block's nodes, in document order against
      # `context`, stopping at the first that fails. `sends` is the send
      # state the block starts with and `stamp` the {Stamp} its effects and
      # events carry.
      #
      # @return [Outcome]
      def execute_block(context, content, stamp, sends = Send::SendState::INITIAL)
        run = Run.new(context:, sends:, effects: [].freeze, raised: [].freeze, pending: [].freeze)
        executed = content.each_with_object([]) do |node, ran|
          ran << node.c_index
          run, failed = top_level(run, node, stamp)
          break ran if failed
        end
        Outcome.new(**run.to_h.except(:pending), executed: executed.freeze)
      end

      # One top-level node run, its recorded condition failures raised
      # against it, then its own failure: `[run, true]` when it failed.
      def top_level(run, node, stamp)
        cause = stamp.cause(node.c_index)
        run, reason = execute_node(run, node, stamp)
        run = drain(run, cause)
        reason.nil? ? [run, false] : [run.raise_events(error_event(reason, cause)), true]
      end

      # One node run: `[run, nil]` on success, else `[run, reason]` with the
      # run the block keeps, which never holds the failing node's effects.
      def execute_node(run, node, stamp)
        after, reason = __send__(RUNNERS.fetch(node.class), run, node, stamp)
        reason.nil? ? [after, nil] : [after.with(effects: run.effects), reason]
      end

      # The pending condition failures raised with `cause`, the top-level
      # node's, in the order they were recorded.
      def drain(run, cause)
        return run if run.pending.empty?

        run.raise_events(*run.pending.map { error_event(_1, cause) }).with(pending: [].freeze)
      end

      # The event a failure raises: a refused `<send>` raises the event its
      # kind names, carrying its id; anything else `error.execution`. The
      # failure, as a predicator value ({Datamodel::ReasonValue.of}), is the
      # event's data.
      def error_event(reason, cause)
        unless reason.is_a?(Send::SendRejected)
          return Event.platform("error.execution", cause, data: Datamodel::ReasonValue.of(reason))
        end

        Event.platform("error.#{reason.kind}", cause, data: Datamodel::ReasonValue.of(reason.reason),
                                                      sendid: reason.send_id)
      end

      # `<raise>`: one internal event named as written.
      def raise_event(run, node, stamp)
        [run.raise_events(Event.internal(node.event, stamp.cause(node.c_index))), nil]
      end

      # `<log>`: the label and the evaluated `expr`, nil without one, as an
      # effect.
      def log(run, node, stamp)
        evaluated = node.expr.nil? ? Send::NONE : Datamodel.evaluate(run.context, node.expr)
        return [run, evaluated.error] unless evaluated.ok?

        [run.effect(Effect::Log.new(label: node.label, value: evaluated.value, c_index: node.c_index, **stamp.fields)),
         nil]
      end

      # `<assign>`: the value evaluated, then written at the location
      # ({Datamodel::Location.write}), which never declares a root. A write
      # that lands answers its change.
      def assign(run, node, stamp)
        context = run.context
        value = Datamodel.evaluate(context, node.value)
        written = value.ok? ? Datamodel::Location.write(context, node.location, value.value) : value
        return [run, written.error] unless written.ok?

        [run.with(context: written.context).effect(change(written, node.location, value.value, node.c_index, stamp)),
         nil]
      end

      # The change a content node's write made: `written` the
      # {Datamodel::Written}, `source` the location as written.
      def change(written, source, new_value, c_index, stamp)
        Effect::DatamodelChange.new(location_path: written.path, location_source: source, new_value:,
                                    prior_value: written.prior_value, d_index: nil, c_index:, **stamp.fields)
      end

      # `<if>`: the first branch whose condition is true runs, an `<else>`
      # always; a condition that fails or is not a boolean is recorded and
      # its branch passed over.
      def if_node(run, node, stamp)
        node.branches.each do |branch|
          evaluated = Datamodel.evaluate_cond(run.context, branch.cond)
          return nested(run, branch.content, stamp) if evaluated.ok? && evaluated.value

          run = run.defer(evaluated.error) unless evaluated.ok?
        end
        [run, nil]
      end

      # A partition or a loop body: each node in order, the first failure
      # wrapped as a {NestedContent} naming the inner node.
      def nested(run, content, stamp)
        content.each do |node|
          run, reason = execute_node(run, node, stamp)
          return [run, NestedContent.new(c_index: node.c_index, reason:)] unless reason.nil?
        end
        [run, nil]
      end

      # `<foreach>`, through {Foreach.execute}.
      def foreach(run, node, stamp) = Foreach.execute(run, node, stamp)

      # `<script>`: the program run through {Datamodel.execute}; its writes
      # before a failure are kept.
      def script(run, node, _stamp)
        executed = Datamodel.execute(run.context, node.program)
        [run.with(context: run.context.with(data: executed.data)), executed.error]
      end

      # `<send>`, through {Send.execute_send}.
      def send_node(run, node, stamp) = sent(run, Send.execute_send(run.context, node, run.sends, stamp))

      # `<cancel>`, through {Send.execute_cancel}.
      def cancel(run, node, stamp) = sent(run, Send.execute_cancel(run.context, node, run.sends, stamp))

      # What a `<send>` or `<cancel>` answered, kept.
      def sent(run, sent)
        kept = run.with(context: sent.context, sends: sent.sends)
        [sent.effects.reduce(kept) { |acc, effect| acc.effect(effect) }, sent.error]
      end
    end
  end
end
