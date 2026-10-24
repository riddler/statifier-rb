# frozen_string_literal: true

module Statifier
  module Driver
    # The checks on what a host passes the driver's calls.
    #
    # @api private
    module Checks
      module_function

      # The options {Statifier.start} takes, as they stand when the host
      # names none.
      START_OPTIONS = {
        session_id: nil, datamodel: {}.freeze, processors: {}.freeze, max_macrostep_rounds: MAX_MACROSTEP_ROUNDS,
        trace: false, clock: nil
      }.freeze

      # {Statifier.start}'s options, after checking them, with the
      # registered `types` and the `session_id`, minted when the host named
      # none.
      #
      # @raise [ArgumentError] for an option {START_OPTIONS} does not name,
      #   or a round budget that is neither a positive Integer nor
      #   `:infinity`
      def start_options(options)
        options = known(options, START_OPTIONS)
        budget(options[:max_macrostep_rounds])
        options.merge(types: registered_types(options[:processors]), session_id: session_id(options[:session_id]))
      end

      # The registered types, sorted, after checking the processors.
      #
      # @raise [TypeError] when `processors` is not a Hash of String types to
      #   objects answering `deliver`
      def registered_types(processors)
        raise TypeError, "processors is a Hash of send types to processors" unless processors.is_a?(Hash)

        processors.each do |type, processor|
          raise TypeError, "a send type is a String, got #{type.inspect}" unless type.is_a?(String)
          raise TypeError, "the processor for #{type.inspect} does not answer deliver" \
            unless processor.respond_to?(:deliver)
        end
        processors.keys.sort.freeze
      end

      # `state`, after checking it, and, unless `processors` is nil, that
      # they register the types the chart was started with.
      #
      # @raise [TypeError] when `state` is not a driver state
      # @raise [ArgumentError] when the processors name other types
      def state(state, processors)
        raise TypeError, "expected a Statifier::Driver::State, got #{state.class}" unless state.is_a?(State)
        return state if processors.nil? || registered_types(processors) == state.send_types

        raise ArgumentError, "processors must register the types the chart started with: #{state.send_types}"
      end

      # The options {Statifier.report_send_failed} takes, as they stand when
      # the host names none.
      REPORT_OPTIONS = { reason: nil, processors: {}.freeze, clock: nil }.freeze

      # A failed-send report's options, after checking them and the chart and
      # the send it names against `state`.
      #
      # @raise [TypeError] when `state` is not a driver state, `machine` is
      #   not a compiled machine or `send` is not a send a processor is handed
      # @raise [ArgumentError] for an option {REPORT_OPTIONS} does not name, or
      #   when `state` is not an execution of `machine`
      def report(machine, state, send, options)
        options = known(options, REPORT_OPTIONS)
        raise TypeError, "expected a compiled machine, got #{machine.class}" unless machine.is_a?(Machine)
        raise TypeError, "expected a Statifier::Effect::Send or SendDelayed, got #{send.class}" \
          unless send.is_a?(Effect::Send) || send.is_a?(Effect::SendDelayed)
        return options if state(state, nil).machine_state.machine == machine

        raise ArgumentError, "the state is not an execution of the machine named"
      end

      # `options` over `defaults`, after checking that `defaults` names
      # every one.
      #
      # @raise [ArgumentError] for an option `defaults` does not name
      def known(options, defaults)
        unknown = options.keys - defaults.keys
        raise ArgumentError, "unknown options: #{unknown.inspect}" unless unknown.empty?

        defaults.merge(options)
      end

      # The session id the host named, or a fresh one, frozen: a host's
      # string is copied first, so the state holds nothing the host can
      # change and the host's string is never frozen in place.
      #
      # @raise [TypeError] when it is neither nil nor a String
      def session_id(session_id)
        return -SessionId.mint if session_id.nil?
        return -session_id if session_id.is_a?(String)

        raise TypeError, "a session id is a String, got #{session_id.class}"
      end

      # The round budget, after checking it.
      def budget(budget)
        return budget if budget == :infinity || (budget.is_a?(Integer) && budget.positive?)

        raise ArgumentError, "max_macrostep_rounds is a positive Integer or :infinity, got #{budget.inspect}"
      end
    end
  end
end
