# frozen_string_literal: true

module Statifier
  class Machine
    # A compiled state. The root at index 0 has the kind `:scxml`, no id and
    # no parent; every other kind is the document's (`:state`, `:parallel`,
    # `:final`, `:history`).
    #
    # - `parent`: the parent's index, nil only for the root;
    # - `last`: the highest index in the state's subtree, so its
    #   descendants are `index + 1` to `last`;
    # - `children`: the direct children's indexes in document order, history
    #   states included, and `history_children` those that are histories;
    # - `initial`: the states a default entry enters, by the specification's
    #   precedence (the `initial` attribute, else the `<initial>` element's
    #   one transition's targets, else the first child); empty for every
    #   kind but a `<state>` and the root;
    # - `history_type`: `:shallow` or `:deep` on a history, nil otherwise;
    # - `transitions`: the selectable transitions' `t_index`es in document
    #   order, empty for a history;
    # - `initial_transition`: the `t_index` of the `<initial>` element's
    #   transition, and `history_default` that of a history's default, each
    #   nil when absent;
    # - `onentry` and `onexit`: one {Block} per element;
    # - `donedata`: a final state's {Donedata}, or nil;
    # - `data`: the `d_index`es of the `<data>` its own `<datamodel>`
    #   declares;
    # - `invoke`: its {Invoke}s in document order.
    #
    # @api private
    State = ::Data.define(
      :index, :id, :kind, :parent, :last, :children, :initial, :history_type, :history_children,
      :transitions, :onentry, :onexit, :initial_transition, :history_default, :donedata, :data,
      :invoke, :location, :attribute_locations
    )

    # A compiled transition. `source` is the index of the state that holds
    # it; `targets` the target states' indexes; `events` each event
    # descriptor split on its dots (`a.b c` is `[["a", "b"], ["c"]]`); `cond`
    # the {Compiled} condition, or nil when none was written, and
    # `cond_location` where it was written, nil exactly when `cond` is;
    # `type` `:external` or `:internal`; `content` its executable content.
    #
    # @api private
    Transition = ::Data.define(
      :t_index, :source, :targets, :events, :cond, :type, :content, :location, :cond_location,
      :attribute_locations
    )

    # One `<onentry>`, `<onexit>` or `<finalize>` block: its executable
    # content.
    #
    # @api private
    Block = ::Data.define(:location, :content)
  end
end
