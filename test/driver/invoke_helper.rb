# frozen_string_literal: true

require_relative "driver_helper"

# What the driver's invoke tests share: building an `<invoke>` of a child
# chart and reading what the child answered.
module DriverInvokeHelper
  include DriverHelper

  NS = %(xmlns="http://www.w3.org/2005/07/scxml" version="1.0")

  # The `<invoke>` of a child whose body is `body`, with `attributes` on the
  # element and `extra` after its content.
  def invoke(body, attributes = %(id="c"), extra = "")
    %(<invoke #{attributes}><content><scxml #{NS}>#{body}</scxml></content>#{extra}</invoke>)
  end

  # The chart whose state `a` invokes `body` and holds `rest`, then `more`
  # after it.
  def invoking(body, rest = "", more = "", attributes: %(id="c"), extra: "")
    %(<state id="a">#{invoke(body, attributes, extra)}#{rest}</state>#{more})
  end

  # The effects a child (or a deeper session) answered, by session id.
  def child_effects(moved, session_id)
    moved.effects.grep(E::Child).select { _1.session_id == session_id }.map(&:effect)
  end

  # The label and value of each log a child answered.
  def child_logs(moved, session_id) = child_effects(moved, session_id).grep(E::Log).map { [_1.label, _1.value] }
end
