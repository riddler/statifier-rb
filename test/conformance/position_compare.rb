# frozen_string_literal: true

module Conformance
  module PositionProperty
    # How the property compares the imported drive's state with the
    # unbroken drive's: `was` the unbroken drive's, `now` the imported one's.
    module PositionCompare
      module_function

      # The fields of a machine state a position carries, as compared. The
      # root is left out of the states to invoke: a chart that stops in the
      # macrostep that starts it holds the root there, as the reference's
      # does, since no invoke pass runs after the stop, and a position never
      # names the root, so an import cannot restore it. The root has no
      # `<invoke>` and a stopped chart runs no invoke pass, so nothing reads
      # it there.
      def carried(state)
        machine_state = state.machine_state
        fields = machine_state.to_h.slice(:configuration, :entered_states, :history, :active_invocations,
                                          :invoke_counter, :running, :status, :macrostep, :microstep, :round, :trace,
                                          :max_macrostep_rounds)
        fields.merge(states_to_invoke: machine_state.states_to_invoke - [0], **sequences(machine_state.sends),
                     datamodel: machine_state.datamodel.transform_values { Predicator::Tagged.encode!(_1) })
      end

      # The send state's two sequences.
      def sequences(sends) = { send_counter: sends.send_counter, timer_counter: sends.timer_counter }

      # nil when the imported drive's state agrees with the unbroken drive's,
      # else the first thing that differs: every field a position carries
      # (the configuration first, a datamodel variable by its encoded text),
      # whether the chart has stopped, and the states it stopped in when it
      # stopped after the import. A chart already stopped at the point is not
      # compared on that last one: the states it stopped in travel in the done
      # effect, never in a position.
      def disagreement(original, imported, stopped_at_point)
        found = field_disagreement(carried(original), carried(imported))
        return found if found

        done_disagreement(Statifier.done?(original).value, Statifier.done?(imported).value, stopped_at_point)
      end

      # The first carried field that differs, or nil.
      def field_disagreement(was, now)
        differing = was.keys.find { was[_1] != now[_1] }
        return datamodel_disagreement(was[:datamodel], now[:datamodel]) if differing == :datamodel

        "#{differing} is #{now[differing].inspect}, the unbroken drive's #{was[differing].inspect}" if differing
      end

      # The first variable, by name, whose text differs.
      def datamodel_disagreement(was, now)
        root = (was.keys | now.keys).sort.find { was[_1] != now[_1] }
        "datamodel.#{root} is #{now[root].inspect}, the unbroken drive's #{was[root].inspect}"
      end

      # nil when the two agree on having stopped, else what differs.
      def done_disagreement(was, now, stopped_at_point)
        return "done? answers #{now.done?}, the unbroken drive's #{was.done?}" unless was.done? == now.done?
        return if !was.done? || stopped_at_point || was.configuration == now.configuration

        "the chart stopped in #{now.configuration}, the unbroken drive's in #{was.configuration}"
      end
    end
  end
end
