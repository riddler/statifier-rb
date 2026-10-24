# frozen_string_literal: true

module Statifier
  module Interpreter
    # The event-name matcher of the specification's section 3.13 (Appendix
    # D's `nameMatch`), as the reference matches.
    #
    # A descriptor matches an event name when its tokens are a prefix of the
    # event's tokens on token boundaries: `error` matches `error.execution`
    # and not `errors.execution`. A trailing `*` token, or the empty token a
    # trailing dot leaves, is dropped before the prefix test, so `*` matches
    # every event, `foo.*` matches `foo` and `foo.bar`, and `foo.` matches as
    # `foo` does. A `*` anywhere else is matched as written.
    #
    # A transition's descriptors arrive split on their dots by the compiler
    # (`Machine::Transition#events`), so both sides here are token lists; an
    # event name is split once per selection round by {tokenize}.
    #
    # @api private
    module NameMatch
      module_function

      # Whether any of `descriptors` (a list of token lists, one per
      # descriptor of a transition's `event` attribute) matches the event
      # whose name is `event_tokens`.
      def name_match?(descriptors, event_tokens) = descriptors.any? { descriptor_match?(_1, event_tokens) }

      # Whether one descriptor's tokens, normalized, are a prefix of
      # `event_tokens`.
      def descriptor_match?(descriptor, event_tokens)
        normalized = normalize(descriptor)
        event_tokens.take(normalized.size) == normalized
      end

      # The descriptor with a trailing `*` or empty token dropped.
      def normalize(descriptor) = ["*", ""].include?(descriptor.last) ? descriptor[0...-1] : descriptor

      # An event name split on its dots, every empty part kept: the empty
      # name is one empty token, as the reference splits it.
      def tokenize(name) = name.empty? ? [""] : name.split(".", -1)
    end
  end
end
