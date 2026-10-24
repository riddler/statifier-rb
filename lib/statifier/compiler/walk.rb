# frozen_string_literal: true

module Statifier
  module Compiler
    # The numbering walk over one chart: made by {Compiler.compile}, used
    # once and discarded. It numbers every state, transition, content node
    # and `<data>` in document order and collects the refusals in four
    # groups (the transitions', the content's, the donedata's and the
    # invokes'), which {Compiler.compile} merges.
    #
    # @api private
    class Walk
      include Numbering
      include Content
      include Parts

      # The pieces the walk has numbered.
      attr_reader :id_to_index, :states, :data

      # The refusals, by group, in the order the groups merge.
      attr_reader :groups

      def initialize
        @id_to_index = {}
        @states = []
        @pending = []
        @data = []
        @data_by_state = Hash.new { |hash, key| hash[key] = [] }
        @c_next = 0
        @groups = { transitions: [], content: [], donedata: [], invoke: [] }
      end

      # Numbers the whole chart, the root at index 0, the root's own `<data>`
      # first.
      def root(document)
        assign_data(document.datamodel_element, 0)
        children, after = siblings(document.states, 1, 0)
        @states[0] = Machine::State.new(
          index: 0, id: nil, kind: :scxml, parent: nil, last: after - 1, children:, history_type: nil,
          initial: root_initial(document.initial, children), history_children: histories(children), **ROOT_PARTS,
          data: owned_data(0),
          **document.to_h.slice(:location, :attribute_locations)
        )
      end

      # The root's default entry: its `initial` attribute, else its first
      # child.
      def root_initial(ids, children) = ids.empty? ? children.first(1).freeze : resolve(ids)

      # Every transition, built now that every id has its index.
      def transitions = @pending.map { build_transition(_1) }.freeze

      # The next content index; a container takes its own before its
      # children's.
      def next_c_index
        @c_next += 1
        @c_next - 1
      end
    end
  end
end
