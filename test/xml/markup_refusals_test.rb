# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# Refusals of comments, processing instructions, the XML declaration and the
# document type declaration.
class MarkupRefusalsTest < Minitest::Test
  include XMLHelper

  # sabotage: answer at the end of the source without refusing in
  # skip_comment (return unless skip_until); the assert_refused fails.
  def test_refuses_an_unterminated_comment
    assert_refused "<a><!-- open", :unterminated_comment, 1, 13
  end

  # sabotage: skip to "-->" in skip_comment (skip_until(/-->/)); the
  # assert_refused fails.
  def test_refuses_a_double_hyphen_inside_a_comment
    assert_refused "<a><!-- a -- b --></a>", :double_hyphen_in_comment, 1, 11
  end

  # sabotage: return when skip_until finds no "?>" in
  # skip_processing_instruction; the assert_refused fails.
  def test_refuses_an_unterminated_processing_instruction
    assert_refused "<a><?pi x", :unterminated_processing_instruction, 1, 10
    assert_refused "<a><? x?></a>", :expected_name, 1, 6
  end

  # sabotage: read an XML declaration anywhere (drop start.offset.zero? in
  # skip_processing_instruction); the assert_refused inside the root fails.
  def test_refuses_an_xml_declaration_anywhere_but_the_start
    assert_refused "<a><?xml version='1.0'?></a>", :misplaced_xml_declaration, 1, 4
    assert_refused "  <?xml version='1.0'?><a/>", :misplaced_xml_declaration, 1, 3
    assert_refused "<?xml version='1.0'?><?xml version='1.0'?><a/>", :misplaced_xml_declaration, 1, 22
  end

  # sabotage: compare the target with == "xml" instead of casecmp? in
  # skip_processing_instruction; the assert_refused for "XML" fails.
  def test_refuses_a_reserved_processing_instruction_target
    assert_refused "<?XML version='1.0'?><a/>", :reserved_target, 1, 1
    assert_equal "a", root("<?xml-model href='x'?><a/>").name
  end

  # sabotage: make the version optional in Markup::DECLARATION; the
  # assert_refused for "<?xml?>" fails.
  def test_refuses_a_malformed_xml_declaration
    ["<?xml?><a/>", "<?xml foo?><a/>", "<?xml encoding='UTF-8'?><a/>",
     "<?xml version='1.0' standalone='maybe'?><a/>", "<?xml version='2.0'?><a/>"].each do |source|
      assert_refused source, :malformed_xml_declaration, 1, 1
    end
    assert_equal "a", root(%(<?xml version="1.1" encoding="utf-8" standalone='yes' ?><a/>)).name
  end

  # sabotage: accept any declared encoding in read_declaration (return
  # after the skip); the assert_refused fails.
  def test_refuses_a_declared_encoding_other_than_utf8
    assert_refused "<?xml version='1.0' encoding='latin1'?><a/>", :unsupported_encoding, 1, 1
  end

  # sabotage: move to the end of the source instead of refusing when an end
  # is missing in skip_doctype (return); the assert_refused for "[" fails.
  def test_refuses_an_unterminated_doctype
    assert_refused "<!DOCTYPE a [", :unterminated_doctype, 1, 14
    assert_refused "<!DOCTYPE a [<?pi x", :unterminated_doctype, 1, 20
    assert_refused "<!DOCTYPE a [<!-- [ -->]><a/>", :unterminated_doctype, 1, 30
  end

  # sabotage: drop the refuse_ambiguous_doctype line in skip_doctype; the
  # assert_refused fails.
  def test_refuses_a_doctype_whose_two_ends_hold_markup_between_them
    assert_refused "<!DOCTYPE a [<!-- ] --><b>]><a/>", :ambiguous_doctype, 1, 1
  end

  # sabotage: end a doctype at the first ">" outside square brackets
  # (DoctypeEnds answering [@bracket, @bracket]); the assert_refused for the
  # quoted ">" fails.
  def test_reads_what_follows_a_doctype_from_where_the_reference_ends_it
    assert_refused %(<!DOCTYPE a [ <!ENTITY x "]>"> ]><a/>), :content_before_root, 1, 32
    assert_refused %(<!DOCTYPE a SYSTEM "x>y"><a/>), :content_before_root, 1, 23
  end
end
