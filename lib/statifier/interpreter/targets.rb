# frozen_string_literal: true

module Statifier
  module Interpreter
    # What a `<send>`'s resolved target and type name, and whether the core
    # refuses them, as the reference judges them (`Statifier.Send.Target`,
    # `Statifier.Send.Types` and `Statifier.Send.Routes` in statifier-ex).
    # Pure over values: whether a destination exists is the driver's.
    #
    # @api private
    module Targets
      # What the driver declares a session can reach: `sessions`, the
      # session ids a `#_scxml_` target may name; `parent?`, whether the
      # session has a parent (the reference's `parent?`, spelled the same);
      # and `invokes`, the invoke ids a `#_` target may name. The session
      # itself and its internal queue need no entry.
      Routes = ::Data.define(:sessions, :parent?, :invokes) do
        # Whether `route` (a {Route}) is reachable.
        def reachable?(route)
          case route.kind
          when :self, :internal then true
          when :session then sessions.include?(route.id)
          when :parent then parent?
          when :invoke then invokes.include?(route.id)
          else false
          end
        end
      end

      # What a resolved target names: `kind` one of `:self` (no target),
      # `:internal`, `:parent`, `:session` and `:invoke` (with `id`, the
      # session or invoke id), and `:invalid` (with `id`, the target as
      # resolved).
      Route = ::Data.define(:kind, :id)

      # The type is neither the SCXML processor's nor a registered one.
      UnsupportedType = ::Data.define(:type)

      # The target names nothing the SCXML processor carries.
      InvalidTarget = ::Data.define(:target)

      # The declared routes do not reach the target.
      UnreachableTarget = ::Data.define(:target)

      module_function

      # Parses a resolved target. Both spellings of the internal and parent
      # targets, with and without the leading `#`, are accepted, as the
      # reference accepts them; anything that is not one of the special
      # targets is invalid.
      #
      # @return [Route]
      def parse_target(target)
        return Route.new(kind: :self, id: nil) if target.nil?
        return Route.new(kind: :invalid, id: target) unless target.is_a?(String)

        case target
        when "#_internal", "_internal" then Route.new(kind: :internal, id: nil)
        when "#_parent", "_parent" then Route.new(kind: :parent, id: nil)
        when /\A#_scxml_(.+)\z/m then Route.new(kind: :session, id: ::Regexp.last_match(1))
        when /\A#_(.+)\z/m then Route.new(kind: :invoke, id: ::Regexp.last_match(1))
        else Route.new(kind: :invalid, id: target)
        end
      end

      # Whether the SCXML processor carries `type`: no type, its short form
      # `scxml`, or its URI.
      def built_in_type?(type)
        type.nil? || type == "scxml" || type == Datamodel::SystemVariables::SCXML_EVENT_PROCESSOR
      end

      # How a resolved type is carried: `:built_in`, `:registered` (a String
      # in `send_types`, the registered types or nil for none) or
      # `:unsupported`. A built-in spelling stays built in whatever the host
      # registered.
      def classify(send_types, type)
        return :built_in if built_in_type?(type)
        return :registered if type.is_a?(String) && send_types&.include?(type)

        :unsupported
      end

      # Why a send is refused, as `[kind, reason]` with `kind` the `error.*`
      # event it raises (`:execution` or `:communication`), or nil. The type
      # is judged first; a registered type's target is its processor's own
      # and never parsed; with `routes` declared, an immediate send's target
      # must be reachable, while a delayed one (`delay_ms` set) is routed
      # when it fires.
      def reject_reason(target, type, delay_ms, send_types, routes)
        case classify(send_types, type)
        when :unsupported then [:execution, UnsupportedType.new(type:)]
        when :registered then nil
        else target_reason(target, delay_ms, routes)
        end
      end

      # A target's refusal under the SCXML processor, or nil.
      def target_reason(target, delay_ms, routes)
        route = parse_target(target)
        return [:execution, InvalidTarget.new(target:)] if route.kind == :invalid
        return nil if routes.nil? || !delay_ms.nil? || routes.reachable?(route)

        [:communication, UnreachableTarget.new(target:)]
      end
    end
  end
end
