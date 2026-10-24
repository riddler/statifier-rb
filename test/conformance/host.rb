# frozen_string_literal: true

require "json"
require_relative "../../lib/statifier"

module Conformance
  # The host a case's host object asks for, as the reference's host-case
  # harness is that host (`Mix.Statifier.Corpus.HostCase` and its
  # `Processor` in lib/mix/statifier/corpus/host_case.ex at the tag the
  # copy names): one processor registered under every type the case's
  # `send_types` names, which records each send the driver hands it and
  # delivers none. A delayed send handed to it is its timer, and it never
  # fires one.
  #
  # Each handed send is written in the case's item shape (the harness's
  # `item/2`): `type`, `target`, `event` with its `name` and, when the send
  # carries a payload, its `data`; `delay_ms` for a delayed send; and
  # `send_id` only when the author named the send, which is when the
  # delivered event carries one. The items handed over the whole drive, in
  # order, are what the drive compares with the case's `expect_sends`.
  #
  # A `<cancel>` that reaches the processor marks `"outcome": "cancelled"`
  # on each delayed send handed before it under the cancel's send id whose
  # expected item, at the position the send was handed in, asks for it (the
  # harness's `cancel_named/2`), so a marked item no cancel reached
  # disagrees. An expected item with no `outcome` claims nothing about a
  # cancel.
  #
  # A send whose expected item, at the position it was handed in, carries
  # `"outcome": "fail"` is marked so and reported failed through
  # {Statifier.report_send_failed} once the driver call that handed it
  # returns, before the drive reads the configuration (the harness's
  # `perform_outcome/4`, which reports through
  # `Statifier.Session.failed_send/3` as soon as it reads the processor's
  # message). A report the driver refuses because the chart has stopped, or
  # because a round budget has halted it, is dropped, as the reference's
  # session drops it.
  #
  # It is a fresh object for every case: it is the host's, so it keeps
  # what it was handed between the driver's calls.
  class Host
    # One handed send: its send id, the expected item at the position it was
    # handed in (nil past the expected list's end), and its item.
    Handed = ::Data.define(:send_id, :expected, :item)

    # The host `item`'s host object asks for: registered under its
    # `send_types`, comparing what it is handed with its `expect_sends`
    # (none of either when it has no host object).
    def self.for(item)
      host = item.fetch("host", {})
      new(host.fetch("send_types", []), host.fetch("expect_sends", []))
    end

    # The refusals of a failed-send report that drop it.
    DROPPED = %i[not_running halted].freeze

    # A host registered under `send_types`, comparing what it is handed with
    # `expected`.
    def initialize(send_types, expected)
      @send_types = send_types
      @expected = expected
      @handed = []
      @failed = []
    end

    # The processors to register: this host under each of its send types.
    def processors = @send_types.to_h { |type| [type, self] }

    # The items handed so far, in order.
    def items = @handed.map(&:item)

    # :pass when the items handed are exactly the expected sends, in order,
    # else the reason.
    def verdict
      return :pass if items == @expected

      "expected the sends handed to the host #{JSON.generate(@expected)}, but got #{JSON.generate(items)}"
    end

    # The driver hands a send of a registered type here, with the event a
    # delivery would carry.
    def deliver(send, event, _context)
      expected = @expected[@handed.size]
      item = Host.item(send, event)
      if fail?(expected)
        item["outcome"] = "fail"
        @failed << send
      end
      @handed << Handed.new(send_id: send.send_id, expected:, item:)
      nil
    end

    # `state` after every send marked failed since the last report is
    # reported through the driver over `machine`, in the order handed, a
    # send handed by a report reported in turn; a refusal DROPPED names is
    # dropped and any other raises.
    def report(machine, state, processors)
      until @failed.empty?
        result = Statifier.report_send_failed(machine, state, @failed.shift, processors:)
        next state = result.value.state if result.ok?
        next if DROPPED.include?(result.error)

        raise "the driver refused the failed-send report: #{result.error.inspect}"
      end
      state
    end

    # The driver tells the processor holding a delayed send of its
    # `<cancel>`.
    def cancel(cancel, _context)
      @handed.map! do |handed|
        next handed unless handed.send_id == cancel.send_id && cancelled?(handed)

        handed.with(item: handed.item.merge("outcome" => "cancelled"))
      end
      nil
    end

    # A handed send in the case's item shape.
    def self.item(send, event)
      item = { "type" => send.type, "target" => send.target, "event" => event_item(event) }
      item["delay_ms"] = send.delay_ms if send.is_a?(Statifier::Effect::SendDelayed)
      item["send_id"] = event.sendid unless event.sendid.nil?
      item
    end

    # The event's `name`, and its `data` unless it carries no payload: the
    # harness leaves out a payload that is undefined, nil or an empty map.
    def self.event_item(event)
      data = event.data
      none = data.equal?(Predicator::UNDEFINED) || data.nil? || data == {}
      none ? { "name" => event.name } : { "name" => event.name, "data" => data }
    end

    private

    # Whether an expected item asks the host to report its send failed.
    def fail?(expected) = expected.is_a?(Hash) && expected["outcome"] == "fail"

    # Whether a handed send is a delayed one its expected item marks as
    # cancelled.
    def cancelled?(handed)
      handed.item.key?("delay_ms") && handed.expected.is_a?(Hash) && handed.expected["outcome"] == "cancelled"
    end
  end
end
