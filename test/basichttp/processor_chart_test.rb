# frozen_string_literal: true

require "test_helper"
require_relative "processor_helper"
require_relative "../driver/driver_helper"

# The Basic HTTP processor registered in a chart: the _ioprocessors
# location, a miss reported back through Statifier.report_send_failed, and
# a send with no target failing in the sending session.
class BasicHTTPProcessorChartTest < Minitest::Test
  include DriverHelper
  include ProcessorHelper

  # sabotage: answer `{}` from ioprocessors_entry; both logged locations are empty.
  def test_a_session_ioprocessors_carries_the_location_under_both_types
    started = start(<<~XML, processors: processor.send_types)
      <state id="a"><onentry>
        <log label="io" expr="[_ioprocessors['basichttp']['location'],
          _ioprocessors['http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor']['location']]"/>
      </onentry></state>
    XML

    assert_equal [["io", ["http://localhost:8080/scxml/s1"] * 2]], logs(started)
  end

  CHART = <<~XML.freeze
    <state id="a">
      <onentry>
        <send event="e.go" type="basichttp" target="#{TARGET}"><param name="n" expr="2"/></send>
        <raise event="e.next"/>
      </onentry>
      <transition event="e.next" target="b"/>
    </state>
    <state id="b"><transition event="error.communication" target="failed"/></state>
    <state id="failed"/>
  XML

  # sabotage: report nothing for a status outside 2xx in post; no miss is reported back.
  def test_a_reported_miss_reaches_the_chart_through_report_send_failed
    misses = []
    processors = processor(Wire.new(status: 503), misses).send_types
    moved = start(CHART, processors:)

    assert_equal %w[b], active(moved)
    assert_equal [:http_status], misses.map(&:reason)
    assert_equal %w[failed], active(reported(moved, misses.first, processors))
  end

  # The chart after the host reports `miss` from `moved`'s state.
  def reported(moved, miss, processors)
    moved(Statifier.report_send_failed(machine(CHART), moved.state, miss.effect, reason: miss.reason, processors:))
  end

  # sabotage: answer nil for a nil target in deliver; event1 is taken first and the chart ends in fail.
  def test_a_send_with_no_target_raises_error_communication_in_the_sending_session
    started = start(<<~XML, processors: processor.send_types)
      <state id="s0">
        <onentry><send event="event1"/><send event="test" type="#{B::EVENT_PROCESSOR}"/></onentry>
        <transition event="error.communication" target="pass"/>
        <transition event="*" target="fail"/>
      </state>
      <final id="pass"/><final id="fail"/>
    XML

    assert_equal %w[pass], Statifier.done?(started.state).value.configuration
  end
end
