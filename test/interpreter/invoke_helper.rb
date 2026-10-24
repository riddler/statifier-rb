# frozen_string_literal: true

require_relative "loop_helper"

# What the invoke tests share: a child's content and the loop's helpers.
module LoopInvokeHelper
  include LoopHelper

  CHILD = %(<content><scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0"><final id="f"/></scxml></content>)

  # The label and value of each log, in order.
  def pairs(effects) = effects.grep(E::Log).map { [_1.label, _1.value] }
end
