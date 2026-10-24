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

    # The reason a case asks for an outcome this host does not perform, or
    # nil: an expected send whose outcome asks the host to report it failed.
    def self.unreported(item)
      expected = item.fetch("host", {}).fetch("expect_sends", [])
      return unless expected.any? { _1.is_a?(Hash) && _1["outcome"] == "fail" }

      "an expected send asks the host to report it failed, which this runner does not report yet"
    end

    # A host registered under `send_types`, comparing what it is handed with
    # `expected`.
    def initialize(send_types, expected)
      @send_types = send_types
      @expected = expected
      @handed = []
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
      @handed << Handed.new(send_id: send.send_id, expected: @expected[@handed.size], item: Host.item(send, event))
      nil
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

    # Whether a handed send is a delayed one its expected item marks as
    # cancelled.
    def cancelled?(handed)
      handed.item.key?("delay_ms") && handed.expected.is_a?(Hash) && handed.expected["outcome"] == "cancelled"
    end
  end
end
