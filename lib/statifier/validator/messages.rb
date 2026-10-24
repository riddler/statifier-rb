# frozen_string_literal: true

module Statifier
  module Validator
    # The message of each reason, made from its detail: the reference's
    # wording, with its quoting of values.
    #
    # @api private
    module Messages
      q = Findings.method(:inspect_value)
      owner = lambda do |detail|
        kind, id = detail[:owner].values_at(:kind, :id)
        element = "<#{kind}>"
        next element if id.nil?

        kind == :initial ? "#{element} on #{q.call(id)}" : "#{element} #{q.call(id)}"
      end

      # The messages of the state, target and default-transition reasons.
      STATES = {
        duplicate_id: ->(d) { "duplicate state id #{q.call(d[:id])}" },
        empty_id: ->(_) { "state id must not be empty - an absent id is legal, an empty one is not" },
        unresolved_target: ->(d) { "transition target #{q.call(d[:id])} does not resolve to a state in the document" },
        unresolved_initial: ->(d) { "initial state #{q.call(d[:id])} does not resolve to a state in the document" },
        initial_not_descendant: lambda do |d|
          parent = d[:parent_id].nil? ? "its parent state, which has no id" : q.call(d[:parent_id])
          "initial state #{q.call(d[:id])} is not a descendant of #{parent}"
        end,
        initial_on_atomic_state: lambda do |d|
          "#{d[:id].nil? ? "a state with no id" : "state #{q.call(d[:id])}"} has no child states to default into"
        end,
        initial_attribute_and_element: lambda do |d|
          "state #{q.call(d[:id])} has both an initial attribute and an <initial> element - at most one is legal"
        end,
        transition_count: ->(d) { "#{owner.call(d)} must have exactly one transition, found #{d[:count]}" },
        transition_missing_target: ->(d) { "#{owner.call(d)} transition must specify a target" },
        transition_forbidden_attribute: ->(d) { "#{owner.call(d)} transition must not specify #{d[:attribute]}" },
        history_bad_parent: lambda do |d|
          "history #{q.call(d[:id])} must be a child of a compound <state> or <parallel>, not #{d[:parent_kind]}"
        end,
        history_bad_type: ->(d) { "history type #{q.call(d[:raw])} must be \"shallow\" or \"deep\"" },
        final_has_states: lambda do |d|
          "state #{q.call(d[:id])} must not be a child of <final> - only onentry, onexit, and donedata are legal there"
        end,
        final_has_transitions: lambda do |d|
          "state #{q.call(d[:id])} is a <final> and must not carry a <transition> - " \
            "only onentry, onexit, and donedata are legal there"
        end,
        final_parent_missing_id: lambda do |_|
          "a state containing a <final> child must have an id - its completion event is named done.state.<id>"
        end,
        default_entry_not_enterable: lambda do |d|
          "state #{q.call(d[:id])} has no initial attribute or <initial> element, and its first child is a " \
            "#{d[:child_kind]} pseudo-state, which cannot be entered by default"
        end
      }.freeze

      # The messages of the root, enumerated-value and data reasons.
      DATA = {
        transition_bad_type: ->(d) { "transition type #{q.call(d[:raw])} must be \"internal\" or \"external\"" },
        scxml_bad_binding: ->(d) { "binding #{q.call(d[:raw])} must be \"early\" or \"late\"" },
        scxml_bad_datamodel: lambda do |d|
          "datamodel #{q.call(d[:raw])} must be one of \"predicator\", \"elixir\", \"null\", \"ecmascript\", " \
            "or \"xpath\""
        end,
        invoke_bad_autoforward: ->(d) { "invoke autoforward #{q.call(d[:raw])} must be \"true\" or \"false\"" },
        bad_namespace: lambda do |d|
          next "the root element declares no namespace - expected xmlns=#{q.call(Findings::SCXML)}" if d[:uri].nil?

          "the root element's namespace #{q.call(d[:uri])} is not the SCXML namespace #{q.call(Findings::SCXML)}"
        end,
        bad_version: lambda do |d|
          next "the root element has no version attribute, expected \"1.0\"" if d[:version].nil?

          "the root element's version #{q.call(d[:version])} must be \"1.0\""
        end,
        donedata_not_on_final: ->(d) { "state #{q.call(d[:id])} carries <donedata>, which is only legal on <final>" },
        donedata_content_and_params: lambda do |d|
          "<donedata> on #{q.call(d[:id])} must not specify both a <content> child and one or more <param> children"
        end,
        content_expr_and_text: lambda do |d|
          "<content> must not specify both an expr attribute (#{q.call(d[:expr])}) and inline #{d[:wording]}"
        end,
        param_expr_and_location: lambda do |d|
          "<param> #{q.call(d[:name])} must not specify both an expr attribute and a location attribute"
        end,
        param_no_value: lambda do |d|
          "<param> #{q.call(d[:name])} must specify either an expr attribute or a location attribute"
        end,
        data_expr_and_src: ->(d) { "<data> #{q.call(d[:id])} must not specify both expr and src" },
        data_value_and_children: lambda do |d|
          "<data> #{q.call(d[:id])} must not specify expr or src together with child content"
        end,
        data_reserved_id: ->(d) { "<data> id #{q.call(d[:id])} must not begin with \"_\" - that prefix is reserved" },
        datamodel_bad_parent: ->(d) { "<datamodel> must not be a child of a #{d[:kind]} state" }
      }.freeze
    end

    # The messages, continued.
    #
    # @api private
    module Messages
      q = Findings.method(:inspect_value)

      # The messages of the executable-content and markup reasons.
      EXECUTABLE = {
        assign_expr_and_text: lambda do |d|
          "<assign> must not specify both an expr attribute (#{q.call(d[:expr])}) and child content"
        end,
        if_elseif_after_else: ->(_) { "<elseif> must not follow <else> - <else> must occur after all <elseif> tags" },
        if_duplicate_else: ->(_) { "<if> must not carry more than one <else> branch" },
        script_no_src_or_text: ->(_) { "<script> must specify either the src attribute or child content" },
        invoke_type_and_typeexpr: ->(_) { "<invoke> must not specify both type and typeexpr" },
        invoke_src_and_srcexpr: ->(_) { "<invoke> must not specify both src and srcexpr" },
        invoke_src_and_content: ->(_) { "<invoke> must not specify src or srcexpr together with a <content> child" },
        invoke_id_and_idlocation: ->(_) { "<invoke> must not specify both id and idlocation" },
        invoke_namelist_and_param: ->(_) { "<invoke> must not specify namelist together with a <param> child" },
        send_event_and_eventexpr: ->(_) { "<send> must not specify both event and eventexpr" },
        send_target_and_targetexpr: ->(_) { "<send> must not specify both target and targetexpr" },
        send_type_and_typeexpr: ->(_) { "<send> must not specify both type and typeexpr" },
        send_id_and_idlocation: ->(_) { "<send> must not specify both id and idlocation" },
        send_delay_and_delayexpr: ->(_) { "<send> must not specify both delay and delayexpr" },
        send_delay_and_internal_target: lambda do |_|
          "<send> must not specify delay or delayexpr when target is \"_internal\""
        end,
        send_namelist_and_content: ->(_) { "<send> must not specify namelist together with a <content> child" },
        send_param_and_content: ->(_) { "<send> must not specify a <param> child together with a <content> child" },
        cancel_sendid_and_sendidexpr: ->(_) { "<cancel> must not specify both sendid and sendidexpr" },
        cancel_no_sendid: ->(_) { "<cancel> must specify exactly one of sendid or sendidexpr" },
        duplicate_attribute: ->(d) { "duplicate attribute #{q.call(d[:attribute])} on <#{d[:element]}>" }
      }.freeze

      # Every error reason's message.
      ERROR = STATES.merge(DATA, EXECUTABLE).freeze

      # Every warning reason's message.
      WARNING = {
        finalize_forbidden_content: ->(d) { "<#{d[:element]}> must not occur inside <finalize>" }
      }.freeze
    end
  end
end
