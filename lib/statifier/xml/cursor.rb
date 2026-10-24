# frozen_string_literal: true

module Statifier
  module XML
    # How a refusal leaves the reader: raised inside one parse and rescued by
    # {XML.parse}, which answers it as a failed {Result}. It never reaches a
    # caller.
    #
    # @api private
    class Refused < StandardError
      # @return [ParseError] the refusal
      attr_reader :error

      # @param error [ParseError] the refusal to carry
      def initialize(error)
        super(error.message)
        @error = error
      end
    end

    # The read position in one document: a byte scanner, and the line and
    # column of the last position asked for, counted forward from there so
    # that the whole document is counted once.
    #
    # @api private
    class Cursor
      # A position: the byte offset and the line and column it sits at.
      Mark = Data.define(:offset, :line, :column)

      WHITESPACE = /[\x20\t\r\n]+/

      # @return [String] the document, as UTF-8
      attr_reader :text

      # @param text [String] the document, valid UTF-8
      def initialize(text)
        @text = text
        @scanner = StringScanner.new(text)
        @known = Mark.new(offset: 0, line: 1, column: 1)
      end

      # @return [Integer] the byte offset of the read position
      def offset = @scanner.pos

      # @return [Boolean] whether the whole document has been read
      def eos? = @scanner.eos?

      # @param pattern [String, Regexp] what to look for at the read position
      # @return [Boolean] whether it is there; nothing is consumed
      def at?(pattern) = !@scanner.match?(pattern).nil?

      # @param pattern [String, Regexp] what to consume
      # @return [String, nil] the text consumed, or nil when it is not there
      def scan(pattern) = @scanner.scan(pattern)

      # @param pattern [String, Regexp] what to consume
      # @return [Integer, nil] the bytes consumed, or nil when it is not there
      def skip(pattern) = @scanner.skip(pattern)

      # @param pattern [Regexp] what to consume up to and through
      # @return [Integer, nil] the bytes consumed, or nil, consuming nothing,
      #   when it does not occur
      def skip_until(pattern) = @scanner.skip_until(pattern)

      # @param group [Integer] a group of the last match
      # @return [String, nil] its text
      def [](group) = @scanner[group]

      # @return [String] the next character, consumed
      def getch = @scanner.getch

      # @return [Integer, nil] the bytes of whitespace consumed, or nil when
      #   there is none
      def skip_whitespace = @scanner.skip(WHITESPACE)

      # Moves the read position.
      #
      # @param offset [Integer] the byte offset to read from next
      # @return [void]
      def move_to(offset)
        @scanner.pos = offset
      end

      # @return [Mark] the read position with its line and column
      def mark
        pos = @scanner.pos
        @known = Mark.new(offset: 0, line: 1, column: 1) if pos < @known.offset
        @known = count_to(pos) if pos > @known.offset
        @known
      end

      # @param from [Mark] where the span starts
      # @param to [Mark] where it ends, exclusive; the read position when omitted
      # @return [Location]
      def span(from, to = mark)
        Location.new(start_line: from.line, start_column: from.column, start_offset: from.offset,
                     end_line: to.line, end_column: to.column, end_offset: to.offset)
      end

      # Refuses the document.
      #
      # @param reason [Symbol] the reason token
      # @param message [String] what is wrong, for a person
      # @param at [Mark] where; the read position when omitted
      # @raise [Refused] always
      def refuse(reason, message, at = mark)
        raise Refused, ParseError.new(reason:, message: "#{message} (line #{at.line}, column #{at.column})",
                                      location: span(at, at))
      end

      # Refuses the document at its end.
      #
      # @param (see #refuse)
      # @raise [Refused] always
      def refuse_at_end(reason, message)
        @scanner.terminate
        refuse(reason, message)
      end

      private

      def count_to(pos)
        chunk = @text.byteslice(@known.offset, pos - @known.offset)
        newline = chunk.rindex("\n")
        return Mark.new(offset: pos, line: @known.line, column: @known.column + chunk.length) unless newline

        Mark.new(offset: pos, line: @known.line + chunk.count("\n"), column: chunk.length - newline)
      end
    end
  end
end
