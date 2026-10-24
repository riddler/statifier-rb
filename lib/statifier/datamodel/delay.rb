# frozen_string_literal: true

module Statifier
  module Datamodel
    # A `<send>` delay in whole milliseconds, read through predicator's own
    # duration parser (`Predicator.parse_duration`), as the reference reads
    # it through its expression language's: one duration vocabulary, so the
    # units are predicator's eight (`y`, `mo`, `w`, `d`, `h`, `m`, `s`,
    # `ms`), a superset of the five the SCXML schema names.
    #
    # The one rewrite is the reference's: the schema admits a bare leading
    # dot (`.5s`) and the parser does not, so a leading `.` becomes `0.`.
    # The sum is the reference's expression language's conversion: a month
    # is thirty days and a year three hundred and sixty five.
    #
    # @api private
    module Delay
      # Each unit's worth in milliseconds.
      WEIGHTS = {
        years: 31_536_000_000, months: 2_592_000_000, weeks: 604_800_000, days: 86_400_000,
        hours: 3_600_000, minutes: 60_000, seconds: 1_000, milliseconds: 1
      }.freeze

      module_function

      # `value` (a delay's text, or what a `delayexpr` evaluated to) in
      # milliseconds. Text is parsed; a `Predicator::Duration` is summed. A
      # map, a date or an instant is 0, as the reference reads any map, which
      # carries none of its duration keys; anything else, and text the parser
      # refuses, is an {InvalidDelay} carrying the value as given.
      #
      # @return [Evaluated] the milliseconds, or the refusal
      def milliseconds(value)
        case value
        when String then parsed(value)
        when Predicator::Duration then Evaluated.new(value: total(value), error: nil)
        when Hash, Predicator::Date, Predicator::DateTime then Evaluated.new(value: 0, error: nil)
        else Evaluated.new(value: nil, error: InvalidDelay.new(value:))
        end
      end

      # Delay text parsed after the leading-dot rewrite.
      def parsed(text)
        parsed = Predicator.parse_duration(text.start_with?(".") ? "0#{text}" : text)
        return Evaluated.new(value: nil, error: InvalidDelay.new(value: text)) unless parsed.ok?

        Evaluated.new(value: total(parsed.value), error: nil)
      end

      # A duration's milliseconds.
      def total(duration) = WEIGHTS.sum { |unit, weight| duration.public_send(unit) * weight }
    end
  end
end
