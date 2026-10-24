# frozen_string_literal: true

module Statifier
  module Lowering
    # The builders of `<datamodel>`, `<data>`, `<donedata>`, `<param>`,
    # `<content>` and `<invoke>`, and the markup slice `<content>` and
    # `<assign>` share.
    #
    # @api private
    module DataModel
      DATAMODEL_SLOTS = { data: %i[data many] }.freeze
      DONEDATA_SLOTS = { content: %i[content one], param: %i[params many] }.freeze
      INVOKE_SLOTS = { param: %i[params many], content: %i[content one], finalize: %i[finalize one] }.freeze
      INVOKE_ATTRIBUTES = %w[type typeexpr src srcexpr id idlocation].freeze
      AUTOFORWARD = { "true" => true, "false" => false }.freeze

      module_function

      # A `<datamodel>`: its `<data>` children.
      def datamodel(element, source)
        filled, errors = States.lower_children(element, source, DATAMODEL_SLOTS)
        [[:datamodel, Document::Datamodel.new(location: element.location, data: Placement.many(filled, :data))],
         errors]
      end

      # A `<data>` holds text, not markup: its text is its value and each
      # element child is misplaced.
      def data(element, _source)
        errors = Executable.misplaced_children(element, "data")
        id = Reading.value(element, "id")
        return [nil, errors + [Errors.missing_attribute("data", "id", element.location)]] if id.nil?

        node = Document::Data.new(
          location: element.location, id:, expr: Reading.value(element, "expr"),
          src: Reading.value(element, "src"), text: Reading.text(element),
          attribute_locations: Reading.locations(element, %w[id expr src])
        )
        [[:data, node], errors]
      end

      # A `<donedata>`: its `<param>` children and its last `<content>`.
      def donedata(element, source)
        filled, errors = States.lower_children(element, source, DONEDATA_SLOTS)
        node = Document::Donedata.new(location: element.location, content: filled[:content],
                                      params: Placement.many(filled, :params))
        [[:donedata, node], errors]
      end

      # A `<param>`, which needs its `name`; its `location` attribute is
      # `param_location`.
      def param(element, source)
        Executable.required(element, source, Executable::NO_SLOTS, "name") do |name, _filled|
          [:param, Document::Param.new(
            location: element.location, name:, expr: Reading.value(element, "expr"),
            param_location: Reading.value(element, "location"),
            attribute_locations: Reading.locations(element, %w[name expr location])
          )]
        end
      end

      # The children of a `<content>` are its payload and are never walked.
      def content(element, source)
        markup, markup_location = markup(element, source)
        node = Document::Content.new(
          location: element.location, expr: Reading.value(element, "expr"), text: Reading.text(element),
          markup:, markup_location:, attribute_locations: Reading.locations(element, %w[expr])
        )
        [[:content, node], Reading::EMPTY]
      end

      # An `<invoke>`: its attributes, its `<param>` children, and its last
      # `<content>` and `<finalize>`.
      def invoke(element, source)
        filled, errors = States.lower_children(element, source, INVOKE_SLOTS)
        fields = INVOKE_ATTRIBUTES.to_h { |name| [name.to_sym, Reading.value(element, name)] }
        node = Document::Invoke.new(
          location: element.location, **fields, namelist: Reading.list(element, "namelist"),
          autoforward: Reading.choice(element, "autoforward", AUTOFORWARD, false),
          params: Placement.many(filled, :params), content: filled[:content], finalize: filled[:finalize],
          attribute_locations: Reading.locations(element, [*INVOKE_ATTRIBUTES, "namelist", "autoforward"])
        )
        [[:invoke, node], errors]
      end

      # The source of an element's children from the first that is not blank
      # text to the last, line breaks as written, and its span; both nil when
      # it has no element child.
      def markup(element, source)
        significant = element.children.reject { |child| child.is_a?(XML::Text) && Reading.blank?(child.value) }
        return [nil, nil] unless significant.any?(XML::Element)

        span = across(significant.first.location, significant.last.location)
        [span.slice(source).freeze, span]
      end

      # The span from the start of `first` to the end of `last`.
      def across(first, last)
        first.with(end_line: last.end_line, end_column: last.end_column, end_offset: last.end_offset)
      end
    end
  end
end
