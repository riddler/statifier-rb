# frozen_string_literal: true

module Statifier
  class Document
    # A `<datamodel>`: its `<data>` children.
    #
    # @api private
    Datamodel = ::Data.define(:location, :data)

    # A `<data>`: `id`, `expr` and `src` as written (`expr` and `src` nil
    # when absent), and `text`, the element's own character data as
    # written.
    #
    # @api private
    Data = ::Data.define(:location, :id, :expr, :src, :text, :attribute_locations)

    # A `<donedata>`: its `<content>` child or nil, and its `<param>`
    # children.
    #
    # @api private
    Donedata = ::Data.define(:location, :content, :params)

    # A `<param>`: `name` as written, `expr` or nil, and `param_location`,
    # its `location` attribute or nil.
    #
    # @api private
    Param = ::Data.define(:location, :name, :expr, :param_location, :attribute_locations)

    # A `<content>`: `expr` or nil; `text`, the element's own character data
    # as written; and `markup` and `markup_location`, as an {Assign} has
    # them.
    #
    # @api private
    Content = ::Data.define(:location, :expr, :text, :markup, :markup_location, :attribute_locations)
  end
end
