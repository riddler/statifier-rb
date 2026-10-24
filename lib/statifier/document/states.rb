# frozen_string_literal: true

module Statifier
  class Document
    # A `<state>`, `<parallel>`, `<final>` or `<history>`: one node for the
    # four, `kind` naming which (`:state`, `:parallel`, `:final`,
    # `:history`), the slots a kind does not use left empty. `id` is the
    # attribute or nil; `initial` is the attribute split on whitespace;
    # `history_type` is `:shallow` or `:deep` on a history (`:shallow` when
    # absent or neither) and nil on every other kind. `onentry` and `onexit`
    # hold one {Block} per element, never flattened.
    #
    # @api private
    State = ::Data.define(
      :kind, :location, :id, :initial, :initial_element, :states, :transitions,
      :onentry, :onexit, :history_type, :donedata, :datamodel_element, :invoke,
      :attribute_locations
    )

    # An `<initial>`: however many transitions were written, none and two
    # included.
    #
    # @api private
    Initial = ::Data.define(:location, :transitions)

    # A `<transition>`. `event` and `target` are the attributes split on
    # whitespace, `cond` the condition's source or nil, `type` `:external`
    # or `:internal` (`:external` when absent or neither). `content` holds
    # its executable content directly: a transition has no block element.
    #
    # @api private
    Transition = ::Data.define(:location, :event, :target, :cond, :type, :content, :attribute_locations)

    # The executable content of one `<onentry>`, `<onexit>` or `<finalize>`
    # element. A written empty element is an empty block.
    #
    # @api private
    Block = ::Data.define(:location, :content)
  end
end
