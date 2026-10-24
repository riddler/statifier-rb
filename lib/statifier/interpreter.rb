# frozen_string_literal: true

require_relative "machine"
require_relative "datamodel"
require_relative "effect"

module Statifier
  # The interpreter's algorithm, ported function for function from the
  # specification's Appendix D pseudocode as the reference ports it: which
  # transitions an event enables ({Selection}, with the event-name matcher
  # {NameMatch}), what those transitions enter ({Entering}), and which
  # states they leave and enter, in order ({ExitEntry}); and what a block of
  # executable content does ({Content}, with `<send>` and `<cancel>` in
  # {Send}).
  #
  # Every function here is pure over plain values: a machine, a
  # configuration, the recorded history, and, where an expression is
  # evaluated, the datamodel. None of them moves a queue or keeps state; each
  # answers what the step that calls it needs as a frozen value (the
  # datamodel a block leaves, its effects and the events it raised
  # included), and the step does the rest.
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
require_relative "interpreter/targets"
require_relative "interpreter/send"
require_relative "interpreter/content"
require_relative "interpreter/foreach"
