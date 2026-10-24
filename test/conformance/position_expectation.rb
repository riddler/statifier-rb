# frozen_string_literal: true

require "json"
require "predicator/tagged"
require_relative "../../lib/statifier"

module Conformance
  # The position a statifier case's step states in its `expect_position`,
  # compared as the reference's harness compares it
  # (`Mix.Statifier.Corpus.PositionExpectation` in
  # lib/mix/statifier/corpus/position_expectation.ex at the tag the copy
  # names): the state's position exported with {Statifier.export_position}
  # and rendered as the JSON value a case writes, with exactly these seven
  # members:
  #
  # - `configuration`, `entered_states` and `states_to_invoke`: each set of
  #   state ids as an array sorted ascending;
  # - `history_values`: each history state's id to its recorded state ids,
  #   an array sorted ascending;
  # - `active_invocations`: one object per live invocation, `state` (the id
  #   of the state that owns the `<invoke>`) and `index` (its ordinal among
  #   that state's own), sorted by state and then by index, the invocation's
  #   id left out;
  # - `running`: the position's boolean as it is;
  # - `datamodel`: every variable but `_event`, `_ioprocessors` and
  #   `_sessionid`, and but `_name` too unless the document's `<scxml>`
  #   element carries a `name` attribute, each value in its JSON form: a
  #   string, a number, a boolean and nil as they are, the undefined value
  #   as nil, a list as an array and a map as an object, member by member.
  #   A date, a datetime or a duration, or a list or map holding one, has no
  #   JSON form, and the step fails naming the variable.
  #
  # The position's other members (the three sequences, `status`, the
  # counters, `trace` and the round budget) are not rendered, as the
  # reference renders none of them. Values compare as JSON values: two
  # numbers agree when they are equal in value, arrays element by element in
  # order, objects member by member.
  module PositionExpectation
    # The system variables the rendering leaves out whatever the document.
    LEFT_OUT_VARIABLES = %w[_event _ioprocessors _sessionid].freeze

    module_function

    # Whether any of item's steps carries an `expect_position`.
    def expected?(item) = item.fetch("steps").any? { _1.key?("expect_position") }

    # nil when every state of machine but the root carries an id, else the
    # reason naming the count of states without one: a case that expects a
    # position needs every state named, since the export refuses a position
    # holding a state it cannot name.
    def named(machine)
      unnamed = machine.states.drop(1).count { _1.id.nil? }
      return if unnamed.zero?

      "a case that expects a position needs every state to carry an id, " \
        "and #{unnamed} state(s) of this document have none"
    end

    # The rendering of state's exported position: `[rendering, nil]`, or
    # `[nil, reason]` for the export's refusal or a datamodel value with no
    # JSON form.
    def render(state)
      exported = Statifier.export_position(state)
      return [nil, "the export refused the position: #{exported.error.reason} #{exported.error.detail}"] \
        unless exported.ok?

      position = exported.value
      datamodel, reason = datamodel(position["datamodel"], state.machine_state.machine.name)
      return [nil, reason] if reason

      [members(position, datamodel), nil]
    end

    # The seven members, the datamodel already rendered.
    def members(position, datamodel)
      { "configuration" => position["configuration"].sort,
        "entered_states" => position["entered_states"].sort,
        "states_to_invoke" => position["states_to_invoke"].sort,
        "history_values" => position["history_values"].transform_values(&:sort),
        "active_invocations" => invocations(position["active_invocations"]),
        "running" => position["running"],
        "datamodel" => datamodel }
    end

    # Each live invocation as its state and index, sorted.
    def invocations(active)
      active.map { { "state" => _1["state"], "index" => _1["invoke_index"] } }.sort_by { [_1["state"], _1["index"]] }
    end

    # The datamodel's texts decoded and rendered: `[datamodel, nil]`, or
    # `[nil, reason]` naming the first variable, by name, with no JSON form.
    # `document_name` is the `<scxml>` element's `name` attribute, nil
    # without one.
    def datamodel(texts, document_name)
      left_out = document_name.is_a?(String) ? LEFT_OUT_VARIABLES : [*LEFT_OUT_VARIABLES, "_name"]
      rendered = {}
      (texts.keys - left_out).sort.each do |name|
        value = Predicator::Tagged.decode!(texts[name])
        json = json_form(value)
        return [nil, "the datamodel's #{name} holds a #{kind(value)} value, which has no JSON form here"] \
          if json.equal?(NONE)

        rendered[name] = json
      end
      [rendered, nil]
    end

    # What json_form answers for a value with no JSON form.
    NONE = Object.new.freeze

    # value's JSON form, or NONE.
    def json_form(value)
      case value
      when Predicator::UNDEFINED, nil then nil
      when String, Integer, Float, true, false then value
      when Array then collect(value.map { json_form(_1) })
      when Hash then object(value)
      else NONE
      end
    end

    # A map's JSON form, member by member in key order, or NONE.
    def object(map)
      keys = map.keys.sort
      values = collect(keys.map { json_form(map[_1]) })
      values.equal?(NONE) ? NONE : keys.zip(values).to_h
    end

    # items, or NONE when one of them is NONE.
    def collect(items) = items.any? { _1.equal?(NONE) } ? NONE : items

    # The kind of a value with no JSON form, as a person reads it.
    def kind(value)
      case value
      when Predicator::Date then "date"
      when Predicator::DateTime then "datetime"
      when Predicator::Duration then "duration"
      when Array then "list"
      when Hash then "map"
      else value.class.name
      end
    end

    # nil when `step`, the one-based step `number`, states no position or
    # state's agrees with it, else the reason.
    def at_step(state, step, number)
      return unless step.key?("expect_position")

      compare(step["expect_position"], state, number, step.fetch("event").fetch("name"))
    end

    # nil when the rendering of state's position is exactly `expected`, a
    # step's `expect_position`, else the reason: the step by its one-based
    # `number` and its event's name, then each member that differs with both
    # values as JSON, or why the position cannot be rendered.
    def compare(expected, state, number, event)
      label = "after step #{number} (#{event}), expect_position"
      actual, reason = render(state)
      return "#{label} cannot be compared: #{reason}" if reason

      differing = differing(expected.is_a?(Hash) ? expected : {}, actual)
      "#{label} differs: #{differing}" unless differing.nil?
    end

    # Each member of the two that differs, with both values, in member
    # order; nil when none does.
    def differing(wanted, actual)
      keys = (wanted.keys | actual.keys).sort.reject { wanted[_1] == actual[_1] }
      return if keys.empty?

      keys.map { "#{_1}: expected #{encode(wanted[_1])}, but got #{encode(actual[_1])}" }.join("; ")
    end

    # A member's value as the reason writes it: nothing for an absent one.
    def encode(value) = value.nil? ? "nothing" : JSON.generate(value)
  end
end
