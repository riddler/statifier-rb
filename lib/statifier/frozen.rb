# frozen_string_literal: true

module Statifier
  # How the package freezes the values it builds and answers.
  #
  # @api private
  module Frozen
    module_function

    # `value`, an effect or an event, as a deeply frozen copy: whatever it
    # carries that is not already shareable is copied before it is frozen,
    # so no object the caller passed in (a datamodel value, the stamp's
    # owner) is frozen in place. The one field that is not copied or frozen
    # is `caller_context`, the host's own opaque value, which the effect
    # carries as the same object, whatever it is.
    def copy(value)
      return Ractor.make_shareable(value, copy: true) unless value.respond_to?(:caller_context)

      Ractor.make_shareable(value.with(caller_context: nil), copy: true).with(caller_context: value.caller_context)
    end
  end
end
