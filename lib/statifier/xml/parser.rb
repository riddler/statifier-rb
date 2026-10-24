# frozen_string_literal: true

module Statifier
  module XML
    # One parse of one document. The element tree is built with an explicit
    # stack, so nesting depth never touches the call stack.
    #
    # @api private
    class Parser
      include CharacterData
      include Markup
      include Tags

      # The constructs inside the root element that open with `<` and are
      # not tags.
      OTHER_MARKUP = /<(?:!--|!\[CDATA\[|\?)/

      # @param text [String] the document, valid UTF-8 with no byte order mark
      def initialize(text)
        @cursor = Cursor.new(text)
        @stack = []
        @run = nil
      end

      # @return [Element] the root element
      # @raise [Refused] when the document is malformed
      def parse
        skip_misc(prolog: true)
        @cursor.refuse(:missing_root, "no root element") if @cursor.eos?
        @cursor.refuse(:content_before_root, "character data before the root element") unless @cursor.at?(START_TAG)
        root = read_root
        skip_misc(prolog: false)
        @cursor.refuse(:content_after_root, "content after the root element") unless @cursor.eos?
        root
      end

      private

      def read_root
        root = open_tag
        root = step until root
        root
      end

      # Reads one construct inside the root element; answers the root once
      # its end tag is read.
      def step
        refuse_unclosed if @cursor.eos?
        return close_tag if @cursor.at?("</")
        return open_tag if start_tag?

        read_content
        nil
      end

      # Whether a start tag begins at the read position: a `<` that opens no
      # other construct.
      def start_tag? = @cursor.at?("<") && !@cursor.at?(OTHER_MARKUP)

      # Reads a comment, a CDATA section, a processing instruction or a run of
      # character data.
      def read_content
        if @cursor.at?("<!--") then skip_comment
        elsif @cursor.at?("<![CDATA[") then read_cdata(run_buffer)
        elsif @cursor.at?("<?") then skip_processing_instruction
        else read_character_data(run_buffer)
        end
      end

      # Reads a start tag; answers the root when the root closes itself.
      def open_tag
        flush
        element, closed = read_start_tag(@stack.last&.scope || Scope::EMPTY)
        @tag_end = @cursor.mark
        return adopt(element.finish(@cursor.span(element.start))) if closed

        @stack.push(element)
        nil
      end

      # Reads an end tag; answers the root when it closes the root.
      def close_tag
        flush
        element = read_end_tag(@stack.pop)
        @tag_end = @cursor.mark
        adopt(element)
      end

      # Appends a finished element to its parent, or answers it when it is
      # the root.
      def adopt(element)
        return element if @stack.empty?

        @stack.last.children << element
        nil
      end

      # The text run open since the last tag. It starts where that tag ends, as
      # the reference's spans do, so a comment or processing instruction
      # before the first character data is inside the span.
      def run_buffer
        @run ||= [@tag_end, +""]
        @run.last
      end

      # Closes the open text run, if any, at the read position: the `<` of the
      # next tag.
      def flush
        return unless @run

        @stack.last.children << Text.new(value: @run.last.freeze, location: @cursor.span(@run.first))
        @run = nil
      end

      def refuse_unclosed
        @cursor.refuse(:unclosed_element, "element <#{@stack.last.name}> is never closed")
      end
    end
  end
end
