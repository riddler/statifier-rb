# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# The members every effect and trace value carries: the counters as they
# stood when it was made.
SURFACE_COUNTERS = %w[macrostep microstep round].freeze

# The fields of a send, with or without a delay.
SURFACE_SEND = %w[c_index data event id_from_author? ordinal owner send_id target type].freeze

# A class with no class methods of its own and these instance methods.
surface_value = ->(*instance) { { "class" => [], "instance" => instance.flatten.sort }.freeze }

# An effect or trace value: these members and the counters.
surface_effect = ->(*members) { surface_value.call(members, SURFACE_COUNTERS) }

# What `require "statifier"` exposes: every public constant reachable from
# Statifier, every module's public module methods, and the class methods
# and public instance methods each public class defines beyond what Data
# (or its superclass) gives it.
SURFACE_MAIN = {
  "constants" => {
    "Statifier" => %w[AcceptsCheck Driver Effect Event Position Result VERSION],
    "Statifier::AcceptsCheck" => [],
    "Statifier::Driver" => %w[Context DeliveryFailure DoneStatus Moved],
    "Statifier::Driver::Context" => [],
    "Statifier::Driver::DeliveryFailure" => [],
    "Statifier::Driver::DoneStatus" => [],
    "Statifier::Driver::Moved" => [],
    "Statifier::Effect" => %w[Autoforward BudgetExhausted Cancel CancelInvoke Child DatamodelChange DatamodelInit
                              Done Invoke Log Send SendDelayed Trace],
    "Statifier::Effect::Autoforward" => [],
    "Statifier::Effect::BudgetExhausted" => [],
    "Statifier::Effect::Cancel" => [],
    "Statifier::Effect::CancelInvoke" => [],
    "Statifier::Effect::Child" => [],
    "Statifier::Effect::DatamodelChange" => [],
    "Statifier::Effect::DatamodelInit" => [],
    "Statifier::Effect::Done" => [],
    "Statifier::Effect::Invoke" => [],
    "Statifier::Effect::Log" => [],
    "Statifier::Effect::Send" => [],
    "Statifier::Effect::SendDelayed" => [],
    "Statifier::Effect::Trace" => %w[CondsEvaluated ContentExecuted Done EntrySet EventDequeued ExitSet
                                     FinalizeAutoforward InvokePass MacrostepStable TransitionsSelected],
    "Statifier::Effect::Trace::CondsEvaluated" => [],
    "Statifier::Effect::Trace::ContentExecuted" => [],
    "Statifier::Effect::Trace::Done" => [],
    "Statifier::Effect::Trace::EntrySet" => [],
    "Statifier::Effect::Trace::EventDequeued" => [],
    "Statifier::Effect::Trace::ExitSet" => [],
    "Statifier::Effect::Trace::FinalizeAutoforward" => [],
    "Statifier::Effect::Trace::InvokePass" => [],
    "Statifier::Effect::Trace::MacrostepStable" => [],
    "Statifier::Effect::Trace::TransitionsSelected" => [],
    "Statifier::Event" => %w[Cause],
    "Statifier::Event::Cause" => [],
    "Statifier::Position" => %w[KEYS Refusal],
    "Statifier::Position::Refusal" => [],
    "Statifier::Result" => []
  },
  "module_methods" => {
    "Statifier" => %w[advance check_accepts compile configuration done? export_position import_position
                      report_send_failed start step],
    "Statifier::Driver" => [],
    "Statifier::Effect" => [],
    "Statifier::Effect::Trace" => [],
    "Statifier::Position" => []
  },
  "classes" => {
    "Statifier::AcceptsCheck" => surface_value.call(%w[undeclared unreachable]),
    "Statifier::Driver::Context" => surface_value.call("session_id"),
    "Statifier::Driver::DeliveryFailure" => surface_value.call("reason"),
    "Statifier::Driver::DoneStatus" => surface_value.call(%w[configuration done done? donedata]),
    "Statifier::Driver::Moved" => surface_value.call(%w[effects state]),
    "Statifier::Effect::Autoforward" => surface_effect.call(%w[event invoke_id state_index]),
    "Statifier::Effect::BudgetExhausted" => surface_effect.call(%w[budget configuration pending_internal_events]),
    "Statifier::Effect::Cancel" => surface_effect.call(%w[c_index caller_context ordinal owner send_id]),
    "Statifier::Effect::CancelInvoke" => surface_effect.call(%w[caller_context invoke_id state_index]),
    "Statifier::Effect::Child" => surface_value.call(%w[effect session_id]),
    "Statifier::Effect::DatamodelChange" => surface_effect.call(%w[c_index d_index location_path location_source
                                                                   new_value owner prior_value]),
    "Statifier::Effect::DatamodelInit" => surface_effect.call("datamodel"),
    "Statifier::Effect::Done" => surface_effect.call(%w[configuration donedata donedata_error]),
    "Statifier::Effect::Invoke" => surface_effect.call(%w[autoforward caller_context content invoke_id invoke_index
                                                          params src state_index type]),
    "Statifier::Effect::Log" => surface_effect.call(%w[c_index label owner value]),
    "Statifier::Effect::Send" => surface_effect.call(SURFACE_SEND),
    "Statifier::Effect::SendDelayed" => surface_effect.call(SURFACE_SEND, %w[caller_context delay_ms]),
    "Statifier::Effect::Trace::CondsEvaluated" => surface_effect.call("evaluations"),
    "Statifier::Effect::Trace::ContentExecuted" => surface_effect.call(%w[c_indexes owner]),
    "Statifier::Effect::Trace::Done" => surface_effect.call(%w[configuration donedata donedata_error]),
    "Statifier::Effect::Trace::EntrySet" => surface_effect.call(%w[configuration indexes]),
    "Statifier::Effect::Trace::EventDequeued" => surface_effect.call(%w[event from]),
    "Statifier::Effect::Trace::ExitSet" => surface_effect.call(%w[configuration indexes]),
    "Statifier::Effect::Trace::FinalizeAutoforward" => surface_effect.call(%w[event finalized forwarded]),
    "Statifier::Effect::Trace::InvokePass" => surface_effect.call(%w[invoke_ids state_indexes]),
    "Statifier::Effect::Trace::MacrostepStable" => surface_effect.call("configuration"),
    "Statifier::Effect::Trace::TransitionsSelected" => surface_effect.call(%w[event t_indexes]),
    "Statifier::Event" => { "class" => %w[external internal platform],
                            "instance" => %w[caller_context cause data invokeid name origin origintype sendid
                                             type] },
    "Statifier::Event::Cause" => surface_value.call("origin", SURFACE_COUNTERS),
    "Statifier::Position::Refusal" => surface_value.call(%w[detail reason]),
    "Statifier::Result" => surface_value.call(%w[error ok? value])
  }
}.freeze

# What `require "statifier/basichttp"` adds to it, the Basic HTTP entry
# point.
SURFACE_BASICHTTP = {
  "constants" => {
    "Statifier::BasicHTTP" => %w[EVENT_PROCESSOR Failure NetHTTPTransport Processor Refusal Request Response
                                 SHORT_TYPE TransportError],
    "Statifier::BasicHTTP::Failure" => [],
    "Statifier::BasicHTTP::NetHTTPTransport" => %w[DEFAULT_TIMEOUT],
    "Statifier::BasicHTTP::Processor" => [],
    "Statifier::BasicHTTP::Refusal" => [],
    "Statifier::BasicHTTP::Request" => [],
    "Statifier::BasicHTTP::Response" => [],
    "Statifier::BasicHTTP::TransportError" => []
  },
  "module_methods" => { "Statifier::BasicHTTP" => %w[decode] },
  "classes" => {
    "Statifier::BasicHTTP::Failure" => surface_value.call(%w[detail effect reason session_id]),
    "Statifier::BasicHTTP::NetHTTPTransport" => { "class" => %w[connection], "instance" => %w[call connect] },
    "Statifier::BasicHTTP::Processor" => surface_value.call(%w[base_url deliver ioprocessors_entry send_types]),
    "Statifier::BasicHTTP::Refusal" => surface_value.call(%w[detail reason]),
    "Statifier::BasicHTTP::Request" => surface_value.call(%w[body headers http_method url]),
    "Statifier::BasicHTTP::Response" => surface_value.call(%w[body headers status]),
    "Statifier::BasicHTTP::TransportError" => surface_value.call
  }
}.freeze

# The public surface, listed whole: an addition or a removal fails here, so
# the surface changes only on purpose. Everything else is a private
# constant. Each entry point is asked of a fresh interpreter, so that what
# the main entry point exposes is read before the Basic HTTP processor is
# loaded.
class SurfaceTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  PROBE = <<~PROBE
    BASE = Data.define
    NAME = Module.instance_method(:name)
    reachable = lambda do |mod|
      inner = mod.constants(false).sort.map { mod.const_get(_1) }.grep(Module)
                 .select { NAME.bind_call(_1).start_with?("\#{NAME.bind_call(mod)}::") }
      [mod] + inner.flat_map { reachable.call(_1) }
    end
    all = reachable.call(Statifier)
    classes, modules = all.partition { _1.is_a?(Class) }
    own = lambda do |klass|
      base = klass < Data ? BASE : klass.superclass
      { "class" => (klass.singleton_methods - base.singleton_methods).sort.map(&:to_s),
        "instance" => (klass.public_instance_methods - base.public_instance_methods).sort.map(&:to_s) }
    end
    puts JSON.generate(
      "constants" => all.to_h { [NAME.bind_call(_1), _1.constants(false).sort.map(&:to_s)] },
      "module_methods" => modules.to_h { [NAME.bind_call(_1), _1.singleton_methods.sort.map(&:to_s)] },
      "classes" => classes.to_h { [NAME.bind_call(_1), own.call(_1)] }
    )
  PROBE

  def surface(*paths)
    requires = paths.map { |path| %(require "#{path}"\n) }.join
    output, status = Open3.capture2(RbConfig.ruby, "-I", LIB, "-rjson", "-e", requires + PROBE)

    assert_predicate status, :success?
    JSON.parse(output)
  end

  # sabotage: drop `:Machine` from Statifier's private_constant list; the
  # main entry point lists Machine among Statifier's constants and the
  # assert_equal fails.
  def test_the_main_entry_point_exposes_exactly_this_surface
    assert_equal SURFACE_MAIN, surface("statifier")
  end

  # sabotage: drop `:Outbound` from BasicHTTP's private_constant list; the
  # Basic HTTP entry point lists Outbound among its constants and the
  # assert_equal fails.
  def test_the_basichttp_entry_point_adds_exactly_the_processor
    statifier = SURFACE_MAIN["constants"]["Statifier"]
    expected = {
      "constants" => SURFACE_MAIN["constants"].merge(SURFACE_BASICHTTP["constants"],
                                                     "Statifier" => (statifier + ["BasicHTTP"]).sort),
      "module_methods" => SURFACE_MAIN["module_methods"].merge(SURFACE_BASICHTTP["module_methods"]),
      "classes" => SURFACE_MAIN["classes"].merge(SURFACE_BASICHTTP["classes"])
    }

    assert_equal expected, surface("statifier", "statifier/basichttp")
  end
end
