# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# Refusals of what surrounds the root element, and the promise that no
# malformed input raises.
class DocumentRefusalsTest < Minitest::Test
  include XMLHelper

  # sabotage: drop the missing_root refusal in Parser#parse; the
  # assert_refused for "" fails.
  def test_refuses_a_document_with_no_root_element
    assert_refused "", :missing_root, 1, 1
    assert_refused "  <!-- c -->  ", :missing_root, 1, 15
  end

  # sabotage: let START_TAG match any "<" (/</); the assert_refused for
  # "<1a/>" fails.
  def test_refuses_character_data_before_the_root_element
    assert_refused "text<a/>", :content_before_root, 1, 1
    assert_refused "<1a/>", :content_before_root, 1, 1
    assert_refused "<!DOCTYPE a><!DOCTYPE a><a/>", :content_before_root, 1, 13
  end

  # sabotage: drop the content_after_root refusal in Parser#parse; the
  # assert_refused for "<a/>text" fails.
  def test_refuses_content_after_the_root_element
    assert_refused "<a/>text", :content_after_root, 1, 5
    assert_refused "<a/><b/>", :content_after_root, 1, 5
    assert_refused "<a/><!DOCTYPE a>", :content_after_root, 1, 5
  end

  # sabotage: re-raise Refused in XML.parse instead of answering it; the
  # flunk in XMLHelper#parse fails.
  def test_never_raises_on_malformed_input
    ["<", "<!", "<!-", "<![CDATA", "<?", "&", "</a>", "<a/", "<a>&#", "<a x='1' x", "\xFF".b].each do |source|
      refute_predicate parse(source), :ok?, source.inspect
    end
  end

  # sabotage: let XML.parse read any object with to_s (drop the is_a? check);
  # the assert_raises fails.
  def test_raises_a_type_error_for_something_that_is_not_a_string
    assert_raises(TypeError) { Statifier::XML.parse(nil) }
  end
end
