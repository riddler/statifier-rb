# frozen_string_literal: true

module Statifier
  class Machine
    # A compiled `<data>`. `value` is, in the specification's precedence, its
    # `expr` (a {Compiled}, or an {Invalid} when it did not compile, which
    # fails when the datamodel binds it), its `src` (a {Src}), its text
    # folded to a {Static} value, or a {Static} nil. `value_location` is
    # where the value was written: the attribute when one was, else the
    # element.
    #
    # @api private
    Data = ::Data.define(:d_index, :id, :value, :location, :value_location)

    # A compiled `<param>`, or one `namelist` entry. `kind` is `:expr` when
    # the value is an `expr` and `:location` when it is a location read;
    # `expr` is a {Compiled} (a `namelist` entry's an {Invalid} when it did
    # not compile); `expr_location` is where it was written.
    #
    # @api private
    Param = ::Data.define(:name, :kind, :expr, :expr_location, :location)

    # A final state's compiled `<donedata>`: its `<content>`'s value as
    # `expr` with `expr_location`, or its {Param}s.
    #
    # @api private
    Donedata = ::Data.define(:location, :expr, :expr_location, :params)

    # A compiled `<invoke>`. `index` is its position among its state's
    # `<invoke>` elements; `type` and `src` fold a literal attribute and its
    # `expr` twin as a `<send>`'s do; `id` and `idlocation` are as written;
    # `namelist` and `params` hold {Param}s, as a `<send>`'s do; `content` is
    # the `<content>` child's value or nil; `finalize` its {Block}, or nil
    # when none was written.
    #
    # @api private
    Invoke = ::Data.define(
      :index, :location, :type, :src, :id, :idlocation, :namelist, :params, :content, :autoforward,
      :finalize, :attribute_locations
    )
  end
end
