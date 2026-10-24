# frozen_string_literal: true

module Statifier
  # The typed chart: what lowering makes of the reader's element tree, one
  # immutable node per SCXML element, and what the compiler reads. The node
  # for `<scxml>` itself is this class; the nodes for the elements under it
  # are the classes nested in it.
  #
  # Three things hold for every node:
  #
  # - Expressions are source. `cond`, `expr`, `array`, `location` and every
  #   other attribute a datamodel evaluates are the text the author wrote,
  #   uncompiled.
  # - The tree is not yet validated. It holds what was written, including
  #   shapes the specification forbids (a `<send>` with both `event` and
  #   `eventexpr`, an `<initial>` with two transitions), for a later check to
  #   report.
  # - `attribute_locations` records only what was written: a frozen Hash
  #   from an attribute's name, as a Symbol, to the span of its value (the
  #   text inside the quotes), holding a key exactly when the author wrote
  #   that attribute. A field's value alone cannot say whether it was
  #   written, because lowering applies the defaults (`binding` is `:early`,
  #   a transition's `type` is `:external`, a history's `type` is
  #   `:shallow`).
  #
  # Every node carries the span of the element it was made from
  # (`location`, or `node_location` on an {Assign}, whose `location` is its
  # attribute) as an {XML::Location}. Every list is frozen and in document
  # order. A field for one child element (`datamodel_element`,
  # `initial_element`, `donedata`, `content`, `finalize`) holds the last such
  # child written.
  #
  # The root fields: `name`, `version`, `datamodel` and `xmlns` are the
  # attributes as written, or nil; `namespace` is the namespace the root's
  # name resolves to (it differs from `xmlns` for a prefixed root); `binding`
  # is `:early` or `:late`, `:early` when absent or neither; `initial` is the
  # attribute split on whitespace; `states` holds the `<state>`,
  # `<parallel>` and `<final>` children, `datamodel_element` the
  # `<datamodel>` child or nil, and `scripts` every `<script>` child.
  #
  # @api private
  Document = ::Data.define(
    :location, :name, :version, :xmlns, :namespace, :datamodel, :binding,
    :initial, :states, :datamodel_element, :scripts, :attribute_locations
  )
end

require_relative "document/states"
require_relative "document/executable"
require_relative "document/data"
require_relative "document/invoke"
