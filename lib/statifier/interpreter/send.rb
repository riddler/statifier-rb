# frozen_string_literal: true

module Statifier
  module Interpreter
    # `<send>` and `<cancel>`, as the reference's send and cancel nodes run
    # them (`Statifier.Machine.Content.Send` and `.Cancel` in statifier-ex),
    # with the event data its `Statifier.EventData` makes.
    #
    # The core delivers nothing and schedules nothing. A `<send>` answers
    # one effect describing the message, {Effect::Send} when it goes now and
    # {Effect::SendDelayed} with its delay when it waits, whatever its
    # target, `#_internal` included; the driver delivers it. A `<cancel>`
    # answers an {Effect::Cancel}.
    #
    # A `<send>` resolves its arguments in the reference's order: the event,
    # the target, the type, the delay, the `namelist` and `<param>` values in
    # document order, then `<content>`. The first that fails discards the
    # send: no id is minted, nothing is written, and the failure is the
    # reason the block's `error.execution` carries. Then the send id is
    # minted (or the author's `id` read) and `idlocation` written; a write
    # that fails discards the send the same way. Only then are the type and
    # the target judged ({Targets.reject_reason}): a refused send keeps its
    # minted id and its `idlocation` write, answers no effect, and fails with
    # a {SendRejected} naming the id and the event it raises.
    #
    # @api private
    module Send
      # What a session carries for its sends from block to block, never a
      # module variable: `send_counter`, the sequence a generated id is
      # minted from (the next id is `send_` and the counter plus one);
      # `timer_counter`, the ordinal sequence every delayed send, every
      # cancel and every immediate send of a registered type advances;
      # `send_types`, the types the host registered a processor for, or nil
      # for none; and `routes`, the {Targets::Routes} the driver last
      # declared, or nil when it declared none.
      SendState = ::Data.define(:send_counter, :timer_counter, :send_types, :routes) do
        # The state with the next generated id minted.
        def mint = with(send_counter: send_counter + 1)

        # The state with the timer counter advanced.
        def tick = with(timer_counter: timer_counter + 1)
      end

      class SendState
        # The send state before the first send.
        INITIAL = new(send_counter: 0, timer_counter: 0, send_types: nil, routes: nil)
      end

      # A `<send>` refused after its id was minted: `send_id`; `kind`,
      # `:execution` or `:communication`, the `error.*` event it raises; and
      # `reason`, the refusal the event's data carries.
      SendRejected = ::Data.define(:send_id, :kind, :reason)

      # What executing a `<send>` or `<cancel>` answered: the `context` and
      # `sends` the block keeps, the `effects` in order, and `error`, the
      # reason it failed, nil when it did not. A failure answers no effect,
      # and an argument failure keeps the context and send state it started
      # with.
      Sent = ::Data.define(:context, :sends, :effects, :error) do
        # @return [Boolean] whether the element succeeded
        def ok? = error.nil?
      end

      # The whitespace a text payload is normalized over, the ASCII set.
      RUNS_OF_SPACE = /[ \t\n\v\f\r]+/

      # A successful evaluation of nil, for an attribute not written.
      NONE = Datamodel::Evaluated.new(value: nil, error: nil)

      module_function

      # Executes the {Machine::Send} `node` against `context` and `sends`;
      # `stamp` ({Content::Stamp}) names the block and the counters.
      #
      # @return [Sent]
      def execute_send(context, node, sends, stamp)
        resolved = resolve_arguments(context, node)
        return failed(context, sends, resolved) unless resolved.is_a?(Hash)

        send_id, minted = mint(node, sends)
        write = node.idlocation && Datamodel::Location.write(context, node.idlocation, send_id)
        return failed(context, sends, write.error) if write && !write.ok?

        judged(node, resolved.merge(send_id:, write:), minted, stamp, write ? write.context : context)
      end

      # The send id and the send state after it: the author's `id`, which
      # consumes no counter, else the next generated id.
      def mint(node, sends) = node.id.nil? ? ["send_#{sends.mint.send_counter}", sends.mint] : [node.id, sends]

      # A send whose id is minted and whose `idlocation` is written, judged
      # ({Targets.reject_reason}): refused, keeping both, or accepted.
      def judged(node, resolved, sends, stamp, context)
        kind, reason = Targets.reject_reason(*resolved.values_at(:target, :type, :delay_ms), sends.send_types,
                                             sends.routes)
        return failed(context, sends, SendRejected.new(send_id: resolved[:send_id], kind:, reason:)) if kind

        accepted(node, resolved, sends, stamp, context)
      end

      # Executes the {Machine::Cancel} `node`: its send id resolved and the
      # effect naming it. An id that names nothing pending is the host's
      # no-op, not a failure.
      #
      # @return [Sent]
      def execute_cancel(context, node, sends, stamp)
        evaluated = Datamodel.evaluate(context, node.sendid)
        return failed(context, sends, evaluated.error) unless evaluated.ok?

        sends = sends.tick
        effect = Effect::Cancel.new(send_id: evaluated.value, c_index: node.c_index, **stamp.fields,
                                    ordinal: sends.timer_counter, caller_context: stamp.caller_context)
        Sent.new(context:, sends:, effects: [effect].freeze, error: nil)
      end

      # A `<content>` body as data, as the reference's event data reads one:
      # blank text is no data; text that predicator reads as a literal (a
      # number, a string, a list, a map) is that value; anything else is the
      # trimmed text with each run of whitespace one space.
      def text_data(text)
        trimmed = text.nil? ? "" : Lowering::Errors.trim(text)
        return Predicator::UNDEFINED if trimmed.empty?

        compiled = Predicator.compile(trimmed)
        evaluated = compiled.ok? ? Predicator.evaluate(compiled.value, {}, on_unbound: :error) : compiled
        evaluated.ok? ? evaluated.value : trimmed.gsub(RUNS_OF_SPACE, " ")
      end

      # `namelist` and `<param>` values (name and value pairs) as data: a
      # Hash, the last of a repeated name winning, or no data when there are
      # none.
      def params_data(pairs) = pairs.empty? ? Predicator::UNDEFINED : pairs.to_h.freeze

      # Every argument resolved, as a Hash, or the reason the first failed.
      def resolve_arguments(context, node)
        resolved = {}
        { event: node.event, target: node.target, type: node.type }.each do |key, expr|
          evaluated = expr.nil? ? NONE : Datamodel.evaluate(context, expr)
          return evaluated.error unless evaluated.ok?

          resolved[key] = evaluated.value
        end
        resolve_rest(context, node, resolved)
      end

      # The delay and the payload, after the first three.
      def resolve_rest(context, node, resolved)
        delay = resolve_delay(context, node.delay)
        return delay.error unless delay.ok?

        data = resolve_data(context, node)
        data.ok? ? resolved.merge(delay_ms: delay.value, data: data.value) : data.error
      end

      # The delay in whole milliseconds ({Datamodel::Delay}), nil for a send
      # with none.
      def resolve_delay(context, delay)
        return NONE if delay.nil?

        evaluated = Datamodel.evaluate(context, delay)
        evaluated.ok? ? Datamodel::Delay.milliseconds(evaluated.value) : evaluated
      end

      # The payload: the `namelist` and `<param>` values, stopping at the
      # first that fails, then, when the node has a `<content>` child, that
      # child's data in their place.
      def resolve_data(context, node)
        pairs = resolve_params(context, node.namelist + node.params)
        return pairs unless pairs.ok?

        content = node.content
        return value(params_data(pairs.value)) if content.nil?

        content.is_a?(Machine::Static) ? value(text_data(content.value)) : Datamodel.evaluate(context, content)
      end

      # A successful evaluation of `value`.
      def value(value) = Datamodel::Evaluated.new(value:, error: nil)

      # Each param's name and value, in order, or the first failure.
      def resolve_params(context, params)
        pairs = params.map do |param|
          evaluated = Datamodel.evaluate(context, param.expr)
          return evaluated unless evaluated.ok?

          [param.name, evaluated.value]
        end
        value(pairs)
      end

      # A failure: no effect, and the context and send state the block keeps.
      def failed(context, sends, error) = Sent.new(context:, sends:, effects: [].freeze, error:)

      # A send that is not refused: the timer counter advanced for a delay
      # or a registered type, its `idlocation` write's change, then its own
      # effect. `resolved` carries the send id and the {Datamodel::Written}
      # of its `idlocation`, nil when it has none.
      def accepted(node, resolved, sends, stamp, context)
        stamps = stamps?(resolved, sends)
        sends = sends.tick if stamps
        write = resolved[:write]
        changes = write ? [Content.change(write, node.idlocation, resolved[:send_id], node.c_index, stamp)] : []
        effect = send_effect(node, resolved, stamp, (sends.timer_counter if stamps))
        Sent.new(context:, sends:, effects: (changes << effect).freeze, error: nil)
      end

      # Whether the send stamps an ordinal: a delay, or a registered type.
      def stamps?(resolved, sends)
        !resolved[:delay_ms].nil? || Targets.classify(sends.send_types, resolved[:type]) == :registered
      end

      # The effect itself, immediate or delayed.
      def send_effect(node, resolved, stamp, ordinal)
        fields = resolved.slice(:event, :target, :type, :data, :send_id)
                         .merge(c_index: node.c_index, **stamp.fields, ordinal:,
                                id_from_author?: !node.id.nil? || !node.idlocation.nil?)
        return Effect::Send.new(**fields) if resolved[:delay_ms].nil?

        Effect::SendDelayed.new(**fields, delay_ms: resolved[:delay_ms], caller_context: stamp.caller_context)
      end
    end
  end
end
