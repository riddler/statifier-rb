# frozen_string_literal: true

module Statifier
  module Position
    # A position's datamodel as text: each variable's value in predicator's
    # tagged-value encoding (`Predicator::Tagged`), and back.
    #
    # @api private
    module Text
      module_function

      # The datamodel's variables, sorted by name, each value encoded:
      # `[texts, nil]`, or `[nil, failure]` naming the first variable, in
      # that order, with no encoding and the codec's reason.
      def encode(datamodel)
        texts = {}
        datamodel.keys.sort.each do |root|
          encoded = Predicator::Tagged.encode(datamodel[root])
          return [nil, { field: "datamodel.#{root}", reason: encoded.error.reason }] unless encoded.ok?

          texts[root] = encoded.value
        end
        [texts, nil]
      end

      # The variables decoded, a deeply frozen Hash of new values: `[data,
      # nil]`, or `[nil, failure]` for the first text, by name, that does not
      # decode, or for a `_sessionid` that is not a String.
      def decode(texts)
        data = {}
        texts.keys.sort.each do |root|
          decoded = Predicator::Tagged.decode(texts[root])
          return [nil, { kind: :undecodable_value, field: "datamodel.#{root}" }] unless decoded.ok?

          data[-root] = decoded.value
        end
        return [nil, { kind: :no_session_id, field: "datamodel.#{SESSION_ID}" }] unless data[SESSION_ID].is_a?(String)

        [Ractor.make_shareable(data), nil]
      end
    end
  end
end
