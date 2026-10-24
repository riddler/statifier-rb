# frozen_string_literal: true

module Statifier
  class Document
    # An `<invoke>`: each attribute as written, or nil, except `namelist`,
    # split on whitespace, and `autoforward`, true only when written
    # `"true"`; its `<param>` children, its `<content>` child or nil, and its
    # `<finalize>` block or nil (a written empty `<finalize/>` is an empty
    # {Block}, so absent and empty differ).
    #
    # @api private
    Invoke = ::Data.define(
      :location, :type, :typeexpr, :src, :srcexpr, :id, :idlocation, :namelist,
      :autoforward, :params, :content, :finalize, :attribute_locations
    )
  end
end
