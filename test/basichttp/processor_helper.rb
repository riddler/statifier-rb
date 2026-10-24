# frozen_string_literal: true

require "statifier/basichttp"

# What the Basic HTTP processor's tests share: the send a test hands the
# processor and a transport double that answers in memory, so no socket is
# opened.
module ProcessorHelper
  B = Statifier::BasicHTTP
  E = Statifier::Effect
  U = Predicator::UNDEFINED
  FORM = "application/x-www-form-urlencoded"
  TARGET = "http://localhost:8080/scxml/s2"
  OWNER = { kind: :onentry, state_index: 2, ordinal: 0 }.freeze

  # A transport double: records each request and answers `status`, or
  # raises `error`.
  class Wire
    attr_reader :requests

    def initialize(status: 204, error: nil)
      @status = status
      @error = error
      @requests = []
    end

    def call(request)
      @requests << request
      raise @error if @error

      B::Response.new(status: @status)
    end
  end

  def send_effect(**fields)
    E::Send.new(event: "ping", target: TARGET, type: B::EVENT_PROCESSOR, data: U, send_id: "send_1", c_index: 3,
                owner: OWNER, macrostep: 1, microstep: 1, round: 0, ordinal: 1, id_from_author?: false, **fields)
  end

  def delayed_effect = E::SendDelayed.new(**send_effect.to_h, delay_ms: 5, caller_context: nil)

  def context = Statifier::Driver::Context.new(session_id: "s1")

  def processor(wire = Wire.new, misses = [])
    B::Processor.new(base_url: "http://localhost:8080/scxml", report: misses.method(:<<), transport: wire)
  end
end
