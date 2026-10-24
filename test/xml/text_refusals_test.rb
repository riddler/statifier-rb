# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# Refusals of references and characters, and of the bytes themselves.
class TextRefusalsTest < Minitest::Test
  include XMLHelper

  # sabotage: answer the literal text for an unknown name in read_reference
  # (fetch(body) { "&#{body};" }); the assert_refused for "&nbsp;" fails.
  def test_refuses_an_entity_other_than_the_five_predefined_ones
    assert_refused "<a>&nbsp;</a>", :unknown_entity, 1, 4
    assert_refused "<!DOCTYPE a [<!ENTITY e 'v'>]><a>&e;</a>", :unknown_entity, 1, 34
  end

  # sabotage: let REFERENCE's body run across whitespace and quotes
  # (/&([^;]+);/); the assert_refused for "& b;" fails.
  def test_refuses_an_ampersand_that_starts_no_reference
    assert_refused "<a>R&D</a>", :malformed_reference, 1, 5
    assert_refused "<a>&amp</a>", :malformed_reference, 1, 4
    assert_refused "<a>&;</a>", :malformed_reference, 1, 4
    assert_refused "<a>& b;</a>", :malformed_reference, 1, 4
    assert_refused '<a><b x="&c"/>d;</a>', :malformed_reference, 1, 10
  end

  # sabotage: drop the xml_char? check in character_reference; the
  # assert_refused for "&#0;" fails.
  def test_refuses_a_character_reference_to_no_xml_character
    ["&#0;", "&#x;", "&#Xe9;", "&#12a;", "&#xG1;", "&#xFFFE;", "&#x110000;", "&#xD800;"].each do |reference|
      assert_refused "<a>#{reference}</a>", :invalid_character_reference, 1, 4
    end
  end

  # sabotage: drop \x00-\x08 from CharacterData::EXCLUDED; the
  # assert_refused for U+0001 in text fails.
  def test_refuses_a_character_xml_does_not_allow
    assert_refused "<a>\u0001</a>", :invalid_character, 1, 4
    assert_refused "<a x=\"\u0001\"/>", :invalid_character, 1, 7
    assert_refused "<a><![CDATA[\u0001]]></a>", :invalid_character, 1, 13
    assert_refused "<a>x\u{FFFF}</a>", :invalid_character, 1, 5
  end

  # sabotage: drop the "]]>" refusal in text_special; the assert_refused
  # fails.
  def test_refuses_a_cdata_end_in_character_data
    assert_refused "<a>x]]>y</a>", :cdata_end_in_text, 1, 5
    assert_equal "x]]y", text_value("<a>x]]y</a>")
  end

  # sabotage: answer the content read so far at the end of the source in
  # cdata_special (return "" when eos); the assert_refused fails.
  def test_refuses_an_unterminated_cdata_section
    assert_refused "<a><![CDATA[x", :unterminated_cdata, 1, 14
  end

  # sabotage: scrub invalid bytes in XML.utf8 (text = text.scrub) instead of
  # refusing; the assert_refused at column 4 fails.
  def test_refuses_bytes_that_are_not_utf8_where_they_start
    assert_refused "<a>\xED\xA0\x80</a>".b, :invalid_encoding, 1, 4
    assert_refused "<a>\n\xFF</a>", :invalid_encoding, 2, 1
  end

  # sabotage: drop the byte order mark refusal in XML.utf8; the
  # assert_refused fails.
  def test_refuses_a_leading_byte_order_mark_as_the_reference_does
    assert_refused "\u{FEFF}<a/>", :byte_order_mark, 1, 1
  end
end
