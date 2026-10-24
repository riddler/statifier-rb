# frozen_string_literal: true

require "test_helper"
require_relative "lowering_helper"

# `<datamodel>`, `<data>`, `<donedata>`, `<param>`, `<content>` and
# `<invoke>`.
class LoweringDataTest < Minitest::Test
  include LoweringHelper

  # sabotage: read src from "expr" in DataModel.data; the assert_equal on
  # the fields fails.
  def test_a_datamodel_holds_its_data_and_each_data_its_attributes_and_text
    data = chart_of(%(<datamodel><data id="a" expr="1"/><data id="b" src="f.json"/><data id="c"> [1, 2] </data>) +
                    %(</datamodel>)).datamodel_element.data

    assert_equal [%w[a b c], ["1", nil, nil], [nil, "f.json", nil]], [data.map(&:id), data.map(&:expr), data.map(&:src)]
    assert_equal ["", "", " [1, 2] "], data.map(&:text)
  end

  # sabotage: place a donedata's params into content (param: %i[content
  # one] in DONEDATA_SLOTS); the assert_equal on the params fails.
  def test_a_donedata_holds_its_params_and_its_content
    donedata = chart_of(%(<final id="f"><donedata><param name="a" expr="1" location="l"/><content expr="c"/>) +
                        %(<param name="b"/></donedata></final>)).states.first.donedata

    assert_equal [%w[a b], ["1", nil], ["l", nil]],
                 [donedata.params.map(&:name), donedata.params.map(&:expr), donedata.params.map(&:param_location)]
    assert_equal "c", donedata.content.expr
  end

  # sabotage: slice a content's markup only when it has no text (return
  # [nil, nil] when any child is text in DataModel.markup); the
  # assert_equal on the markup fails.
  def test_a_content_keeps_its_text_and_the_markup_of_its_element_children
    plain, mixed = chart_of(%(<final><donedata><content> x </content></donedata></final>) +
                            %(<final><donedata><content> a <b c="1"/> d </content></donedata></final>))
                   .states.map { _1.donedata.content }

    assert_equal [" x ", nil, nil], [plain.text, plain.markup, plain.markup_location]
    assert_equal [%( a <b c="1"/> d ), " a  d "], [mixed.markup, mixed.text]
  end

  # sabotage: slice the source as given (drop the transcoding in
  # Lowering.utf8); the assert_equal on the UTF-16 markup fails.
  def test_slices_markup_from_the_document_as_the_reader_read_it
    source = %(<scxml><final><donedata><content> <x a="\u00e9"/> </content></donedata></final></scxml>)

    [source, source.b, source.encode("UTF-16LE")].each do |given|
      content = Statifier::Lowering.lower(Statifier::XML.parse(given).value, given).value.states.first.donedata.content

      assert_equal [%(<x a="\u00e9"/>), Encoding::UTF_8], [content.markup, content.markup.encoding]
    end
  end

  # sabotage: map "true" to false in DataModel::AUTOFORWARD; the
  # assert_equal on autoforward fails.
  def test_an_invoke_reads_its_attributes_with_autoforward_false_unless_true
    invokes = state_of(<<~XML).invoke
      <state><invoke type="t" typeexpr="te" src="s" srcexpr="se" id="i" idlocation="il" namelist="a b"
              autoforward="true"/><invoke autoforward="yes"/></state>
    XML

    assert_equal(%w[t te s se i il], fields(invokes.first, :type, :typeexpr, :src, :srcexpr, :id, :idlocation))
    assert_equal [%w[a b], true, false], [invokes.first.namelist, invokes.first.autoforward, invokes.last.autoforward]
    assert_equal([8, 1], invokes.map { _1.attribute_locations.size })
  end

  # sabotage: keep the first finalize (`||=` for a :one field in
  # Placement.fold); the assert_equal on the finalize content fails.
  def test_an_invoke_holds_params_content_and_a_finalize_absent_apart_from_empty
    with, without = state_of(%(<state><invoke><param name="p"/><content expr="c"/><finalize/>) +
                             %(<finalize><raise event="r"/></finalize></invoke><invoke/></state>)).invoke

    assert_equal [["p"], "c", ["r"]], [with.params.map(&:name), with.content.expr, with.finalize.content.map(&:event)]
    assert_nil without.finalize
    assert_equal [[], nil], [without.params, without.content]
  end

  # sabotage: answer a finalize as an onentry (tag :onentry in
  # States.finalize); the empty finalize is misplaced and the chart refused.
  def test_a_written_empty_finalize_is_an_empty_block
    finalize = state_of(%(<state><invoke><finalize/></invoke></state>)).invoke.first.finalize

    assert_equal [], finalize.content
  end
end
