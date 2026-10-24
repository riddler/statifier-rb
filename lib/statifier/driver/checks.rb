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
        unknown = options.keys - START_OPTIONS.keys
        raise ArgumentError, "unknown options: #{unknown.inspect}" unless unknown.empty?

        options = START_OPTIONS.merge(options)
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

      # The session id the host named, or a fresh one.
      #
      # @raise [TypeError] when it is neither nil nor a String
      def session_id(session_id)
        return SessionId.mint if session_id.nil?
        return session_id if session_id.is_a?(String)

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
