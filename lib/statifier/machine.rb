# frozen_string_literal: true

module Statifier
  # The compiled chart the interpreter steps: what {Compiler.compile} makes of
  # a validated {Document}, and the `value` of a successful {Statifier.compile}.
  # It is a frozen value, deeply: every node, list and compiled expression in
  # it is frozen, so it may be shared between executions and Ractors.
  #
  # Every state is interned to an index in document order. Index 0 is the
  # `<scxml>` root, made from the document's own fields: the specification
  # treats `<scxml>` as a state when it computes a transition's domain, and
  # giving it an index removes the special case. A state's descendants are
  # exactly the indexes after its own up to and including its `last`, so
  # ancestry and document order are integer comparisons.
  #
  # Transitions and `<data>` elements have their own dense index spaces,
  # `t_index` and `d_index`, assigned in document order. Executable content
  # carries its `c_index` on each node and sits inline in the block,
  # transition, branch or loop body that holds it.
  #
  # The fields: `states`, every {State} by index; `id_to_index`, the index of
  # every state written with a non-empty id; `transitions`, every
  # {Transition} by `t_index`; `data_elements`, every {Data} by `d_index`,
  # the root's own first; `global_scripts`, the `<script>` children of
  # `<scxml>` (each a {Program} or an {Invalid}), run once when the chart
  # starts; `name`, `datamodel` and `binding`, the root's attributes;
  # `location`, the root's span; and `warnings`, the
  # {Validator::Warning}s the chart was compiled with.
  #
  # Its shape is internal and may change in any release: a host passes a
  # machine on and reads none of its members.
  #
  # @api private
  Machine = ::Data.define(
    :states, :id_to_index, :transitions, :data_elements, :global_scripts,
    :name, :datamodel, :binding, :location, :warnings
  ) do
    # @return [State] the state at `index`
    # @raise [IndexError] when the machine holds no such state
    def state(index) = states.fetch(index)

    # Whether `descendant` sits inside `ancestor`. Proper: a state is not its
    # own descendant.
    def descendant?(descendant, ancestor) = ancestor < descendant && descendant <= state(ancestor).last

    # Whether the state has no child states. A final state is atomic.
    def atomic?(index) = state(index).children.empty?

    # Whether the state is compound: a `<state>` or the root with at least
    # one child. A parallel is never compound.
    def compound?(index)
      node = state(index)
      %i[state scxml].include?(node.kind) && !node.children.empty?
    end

    # Whether the state is a `<parallel>`.
    def parallel?(index) = state(index).kind == :parallel

    # Whether the state is a `<final>`.
    def final?(index) = state(index).kind == :final

    # Whether the state is a `<history>` pseudo-state.
    def history?(index) = state(index).kind == :history

    # The state's child states in document order, history pseudo-states left
    # out (the specification's `getChildStates`).
    def child_states(index)
      node = state(index)
      node.children - node.history_children
    end

    # The state's proper ancestors, nearest first and the root last (the
    # specification's `getProperAncestors` with no bound).
    def proper_ancestors(index)
      ancestors = []
      parent = state(index).parent
      until parent.nil?
        ancestors << parent
        parent = state(parent).parent
      end
      ancestors
    end

    # The least common compound ancestor of `indexes` (the specification's
    # `findLCCA`): the nearest proper ancestor of the first index that is
    # compound and holds every index as a descendant, or nil when none does.
    # A parallel never qualifies.
    def lcca(indexes)
      return nil if indexes.empty?

      proper_ancestors(indexes.first).find do |candidate|
        compound?(candidate) && indexes.all? { descendant?(_1, candidate) }
      end
    end
  end
end

require_relative "machine/values"
require_relative "machine/states"
require_relative "machine/content"
require_relative "machine/data"
