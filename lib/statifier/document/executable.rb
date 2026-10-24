# frozen_string_literal: true

module Statifier
  class Document
    # A `<raise>`: `event` is the attribute as written, one string, not
    # split.
    #
    # @api private
    Raise = ::Data.define(:location, :event, :attribute_locations)

    # A `<log>`: `label` and `expr` as written, or nil.
    #
    # @api private
    Log = ::Data.define(:location, :label, :expr, :attribute_locations)

    # An `<assign>`. `location` is its `location` attribute, the path
    # assigned to; the element's span is `node_location`. `expr` is the
    # attribute or nil. `text` is the element's own character data, as
    # written. `markup` is the source of its element children, from the
    # first child that is not blank text to the last, sliced from the
    # document with its line breaks as they are there, and
    # `markup_location` its span; both are nil when it has no element child.
    #
    # @api private
    Assign = ::Data.define(:location, :node_location, :expr, :text, :markup, :markup_location, :attribute_locations)

    # An `<if>`: one {Branch} for the `<if>` itself, then one per `<elseif>`
    # and `<else>`, each holding the executable content up to the next.
    #
    # @api private
    If = ::Data.define(:location, :branches)

    class If
      # One partition of an `<if>`. `location` is the span of the element
      # that opened it (the `<if>`, an `<elseif>` or an `<else>`); `cond` is
      # that element's condition source, nil for an `<else>`.
      #
      # @api private
      Branch = ::Data.define(:location, :cond, :content, :attribute_locations)
    end

    # A `<foreach>`: `array`, `item` and `index` as written (`index` nil
    # when absent), and its executable content.
    #
    # @api private
    Foreach = ::Data.define(:location, :array, :item, :index, :content, :attribute_locations)

    # A `<script>`: `text` is its program, the element's own character data
    # as written. A script with `src` does not lower, so `src` is always nil
    # and `attribute_locations` empty.
    #
    # @api private
    Script = ::Data.define(:location, :text, :src, :attribute_locations)

    # A `<send>`: each attribute as written, or nil, except `namelist`,
    # split on whitespace; its `<param>` children and its `<content>` child.
    #
    # @api private
    Send = ::Data.define(
      :location, :event, :eventexpr, :target, :targetexpr, :type, :typeexpr, :id,
      :idlocation, :delay, :delayexpr, :namelist, :params, :content, :attribute_locations
    )

    # A `<cancel>`: `sendid` and `sendidexpr` as written, or nil.
    #
    # @api private
    Cancel = ::Data.define(:location, :sendid, :sendidexpr, :attribute_locations)
  end
end
