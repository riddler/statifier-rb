# frozen_string_literal: true

require_relative "machine"
require_relative "datamodel"
require_relative "effect"
require_relative "event"

module Statifier
  # The interpreter's algorithm, ported function for function from the
  # specification's Appendix D pseudocode as the reference ports it: which
  # transitions an event enables ({Selection}, with the event-name matcher
  # {NameMatch}), what those transitions enter ({Entering}), and which
  # states they leave and enter, in order ({ExitEntry}); and what a block of
  # executable content does ({Content}, with `<send>` and `<cancel>` in
  # {Send}); and the loop over them ({Loop}, with {Step}, {Blocks},
  # {Macrostep} and {Stop}), which starts a chart, takes an event and runs
  # each macrostep over a {MachineState}.
  #
  # Every function here is pure over plain values: a machine, a
  # configuration, the recorded history, and, where an expression is
  # evaluated, the datamodel. Below the loop none of them moves a queue or
  # keeps state; each answers what the step that calls it needs as a frozen
  # value (the datamodel a block leaves, its effects and the events it raised
  # included). The loop threads one {MachineState} through them and answers
  # the state it leaves, never changing the one it was given.
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
require_relative "interpreter/machine_state"
require_relative "interpreter/blocks"
require_relative "interpreter/step"
require_relative "interpreter/macrostep"
require_relative "interpreter/stop"
require_relative "interpreter/loop"
