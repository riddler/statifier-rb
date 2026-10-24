# frozen_string_literal: true

module Statifier
  module Interpreter
    module Invoke
      # An `<invoke>`'s arguments resolved against one context, in the
      # reference's order (`invoke_one`'s `with` in `Statifier.Interpreter`,
      # statifier-ex): the type, the source, the `namelist` and `<param>`
      # values in document order, then `<content>`. The first failure
      # abandons the whole element, unlike a `<donedata>` param, which fails
      # alone.
      #
      # @api private
      module Arguments
        module_function

        # The resolved `type:`, `src:`, `params:` and `content:` as a Hash,
        # or the reason the first that failed carries.
        def resolve(context, invoke)
          resolved = {}
          { type: invoke.type, src: invoke.src }.each do |key, expr|
            evaluated = expr.nil? ? Send::NONE : Datamodel.evaluate(context, expr)
            return evaluated.error unless evaluated.ok?

            resolved[key] = evaluated.value
          end
          rest(context, invoke, resolved)
        end

        # The params and the content, after the type and the source.
        def rest(context, invoke, resolved)
          pairs = Send.resolve_params(context, invoke.namelist + invoke.params)
          return pairs.error unless pairs.ok?

          content = content(context, invoke.content)
          return content.error unless content.ok?

          resolved.merge(params: Send.params_data(pairs.value), content: content.value)
        end

        # The `<content>` child's data: nil for none, its body read as a
        # `<send>`'s is ({Send.text_data}), or its `expr`'s value.
        def content(context, content)
          return Send::NONE if content.nil?
          return Send.value(Send.text_data(content.value)) if content.is_a?(Machine::Static)

          Datamodel.evaluate(context, content)
        end
      end
    end
  end
end
