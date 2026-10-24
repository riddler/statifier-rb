# frozen_string_literal: true

require_relative "machine"
require_relative "datamodel"

module Statifier
  # The interpreter's algorithm, ported function for function from the
  # specification's Appendix D pseudocode as the reference ports it: which
  # transitions an event enables ({Selection}, with the event-name matcher
  # {NameMatch}), what those transitions enter ({Entering}), and which
  # states they leave and enter, in order ({ExitEntry}).
  #
  # Every function here is a pure query over plain values: a machine, a
  # configuration, the recorded history, and, where a condition is
  # evaluated, the datamodel. None of them runs executable content, moves a
  # queue or keeps state; each answers what the step that calls it needs as
  # a frozen value, and the step does the rest.
  #
  # @api private
  module Interpreter
    # What selection, exit and entry read of an execution, the two globals
    # the pseudocode keeps beside the chart: `machine`, the compiled chart;
    # `configuration`, the indexes of the active states as a frozen Array in
    # ascending index order (document order); and `history`, the recorded
    # value of each history state that has one, a frozen Hash of the history
    # state's index to a frozen ascending Array of state indexes.
    Snapshot = ::Data.define(:machine, :configuration, :history) do
      # Whether the state at `index` is active.
      def active?(index) = configuration.include?(index)
    end
  end
end

require_relative "interpreter/name_match"
require_relative "interpreter/selection"
require_relative "interpreter/entering"
require_relative "interpreter/exit_entry"
