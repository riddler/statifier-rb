# frozen_string_literal: true

module Statifier
  module Driver
    # A send of a registered type handed to the host's processor, and a send
    # that processor could not deliver, as the reference's session hands a
    # send to its processor's `deliver/3` and writes a failed send in
    # `Statifier.Session.failed_send/3`. Each function answers
    # `[work, deferred effects]`, as {Routing}'s do.
    #
    # @api private
    module Delivery
      module_function

      # A registered type's send handed to its processor with the event a
      # delivery would carry; a delayed one is held under its send id, so a
      # `<cancel>` of that id reaches the processor. A {DeliveryFailure} the
      # processor answers fails the send here, at its place in the call, as
      # the reference raises the failure its processor plans in `deliver/3`.
      # The failure counts against the call's budget as an undelayed send
      # onto the internal queue does, so a chart that sends again on every
      # failure halts rather than running on within the call.
      def hand_off(work, send)
        work = hold(work, send) if send.is_a?(Effect::SendDelayed)
        event = Routing.delivered_event(send, work.state.session_id)
        answered = work.processors.fetch(send.type).deliver(send, event, work.context)
        return [work, []] unless answered.is_a?(DeliveryFailure)

        Routing.counted(work) { failed(_1, send) }
      end

      # The work with the send's type holding a delayed send under its id.
      def hold(work, send)
        types = (work.state.held_sends.fetch(send.send_id, []) | [send.type]).sort.freeze
        work.with_state(held_sends: work.state.held_sends.merge(send.send_id => types).freeze)
      end

      # A send its processor could not deliver, as the reference's
      # `Statifier.Session.failed_send/3` writes it: `error.communication`
      # on the internal queue, its origin the send's content and its
      # `sendid` the send's id whether or not its author named it.
      def failed(work, send) = Routing.communication_error(work, send, sendid: send.send_id)
    end
  end
end
