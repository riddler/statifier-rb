# frozen_string_literal: true

module Statifier
  class Machine
    # The compiled executable content. Every node carries its `c_index`, its
    # place in one dense index space over the whole chart in document order
    # (a container before its children), the index an execution error names.
    # An expression is a {Compiled} or a {Static}; one whose failure is
    # deferred to when it runs is an {Invalid}.

    # A `<raise>`: `event` as written.
    #
    # @api private
    Raise = ::Data.define(:c_index, :event, :location)

    # A `<log>`: `label` as written, `expr` a {Compiled} or nil, and
    # `expr_location` where it was written, nil when it was not.
    #
    # @api private
    Log = ::Data.define(:c_index, :label, :expr, :location, :expr_location)

    # An `<assign>`. `location` is the path assigned to, as written, and
    # `location_location` its span; `node_location` is the element's span.
    # `value` is its `expr` (a {Compiled}, or an {Invalid} when it did not
    # compile), else its markup children as a {Static} string, else its text
    # folded to a {Static} value; `expr_location` is where `expr` was
    # written, nil when it was not.
    #
    # @api private
    Assign = ::Data.define(:c_index, :location, :node_location, :value, :location_location, :expr_location)

    # An `<if>`: one {Branch} for the `<if>` and one per `<elseif>` and
    # `<else>`.
    #
    # @api private
    If = ::Data.define(:c_index, :location, :branches)

    class If
      # One branch: `cond` a {Compiled}, nil for an `<else>`, with
      # `cond_location`; `content` the content up to the next branch.
      #
      # @api private
      Branch = ::Data.define(:cond, :cond_location, :content)
    end

    # A `<foreach>`: `array` a {Compiled}, `item` and `index` as written
    # (`index` nil when absent), each with the span of its attribute
    # (`index_location` nil when `index` is), and its content.
    #
    # @api private
    Foreach = ::Data.define(
      :c_index, :location, :array, :array_location, :item, :item_location, :index, :index_location, :content
    )

    # A `<script>`: `program` a {Program}, or an {Invalid} when its body did
    # not compile; `node_location` the element's span.
    #
    # @api private
    Script = ::Data.define(:c_index, :program, :node_location)

    # A `<send>`. `event`, `target`, `type` and `delay` each fold a literal
    # attribute and its `expr` twin into one expression: a {Static} for the
    # literal, a {Compiled} for the twin, nil when neither was written.
    # `id` and `idlocation` are as written; `namelist` holds a {Param} per
    # entry (a location read by its own name, an {Invalid} when it did not
    # compile), `params` a {Param} per `<param>`, and `content` the
    # `<content>` child's value, or nil.
    #
    # @api private
    Send = ::Data.define(
      :c_index, :location, :event, :target, :type, :id, :idlocation, :delay, :namelist, :params, :content,
      :attribute_locations
    )

    # A `<cancel>`: `sendid` a {Static} for the literal attribute, else a
    # {Compiled} for `sendidexpr`.
    #
    # @api private
    Cancel = ::Data.define(:c_index, :location, :sendid, :attribute_locations)
  end
end
