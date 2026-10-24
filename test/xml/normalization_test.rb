# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# The two normalizations an XML processor owes before a value exists:
# attribute values per XML 1.0 section 3.3.3 and line breaks in character
# data per section 2.11, each read from the raw source as the reference
# reads them (statifier-ex at the vendored tag, Statifier.Parser.Location's
# normalize_attribute_value/3 and normalize_character_data/3).
class NormalizationTest < Minitest::Test
  include XMLHelper

  # sabotage: append the raw character instead of a space for a literal TAB
  # in value_special; the assert_equal on "a b" for "a\tb" fails.
  def test_a_literal_tab_lf_or_cr_in_an_attribute_value_becomes_a_space
    assert_equal "a b", attribute_value(%(<a x="a\tb"/>))
    assert_equal "a b", attribute_value(%(<a x="a\nb"/>))
    assert_equal "a b", attribute_value(%(<a x="a\rb"/>))
  end

  # sabotage: let line_break consume only the CR (pattern /\r/); the
  # assert_equal on "a b" for "a\r\nb" fails.
  def test_a_literal_cr_lf_pair_in_an_attribute_value_becomes_one_space
    assert_equal "a b", attribute_value(%(<a x="a\r\nb"/>))
    assert_equal "a  b", attribute_value(%(<a x="a\r\n\r\nb"/>))
  end

  # sabotage: map every character reference's whitespace to a space in
  # read_reference; the assert_equal on "a\nb" for "a&#10;b" fails.
  def test_a_character_reference_keeps_its_character_in_an_attribute_value
    assert_equal "a\nb", attribute_value(%(<a x="a&#10;b"/>))
    assert_equal "a\tb", attribute_value(%(<a x="a&#9;b"/>))
    assert_equal "a\rb", attribute_value(%(<a x="a&#xD;b"/>))
    assert_equal "\n ", attribute_value(%(<a x="&#10;\n"/>))
  end

  # sabotage: strip the value in read_value; the assert_equal on "  a  "
  # fails.
  def test_nothing_in_an_attribute_value_is_trimmed_or_collapsed
    assert_equal "  a  ", attribute_value(%(<a x="  a  "/>))
    assert_equal "a   b", attribute_value(%(<a x="a   b"/>))
    assert_equal "a < b", attribute_value(%(<a x="a &lt; b"/>))
  end

  # sabotage: stop VALUE_RUNS['"'] at either quote; the assert_equal on the
  # two values fails.
  def test_each_quote_style_holds_the_other
    assert_equal ['say "hi"', "it's"], root(%(<a x='say "hi"' y="it's"/>)).attributes.map(&:value)
  end

  # sabotage: append "\r" instead of "\n" in text_special's line_break; the
  # assert_equal on "a\nb" for "a\r\nb" fails.
  def test_a_literal_cr_lf_pair_or_lone_cr_in_text_folds_to_one_lf
    assert_equal "a\nb", text_value("<a>a\r\nb</a>")
    assert_equal "c\nd", text_value("<a>c\rd</a>")
    assert_equal "q\n\nr", text_value("<a>q\r\n\r\nr</a>")
  end

  # sabotage: fold every "\r" in the finished text in flush; the assert_equal
  # on "e\rf" fails.
  def test_a_cr_decoded_from_a_reference_stays_a_cr_in_text
    assert_equal "e\rf", text_value("<a>e&#xD;f</a>")
  end

  # sabotage: append the raw CR in cdata_special; the assert_equal on "g\nh"
  # fails.
  def test_line_breaks_fold_inside_a_cdata_section
    assert_equal "g\nh", text_value("<a><![CDATA[g\r\nh]]></a>")
  end

  # sabotage: answer the raw "\r" for a CR in text_special and fold the
  # finished run with gsub(/\r\n?/, "\n") in flush; the assert_equal on
  # "i\n\nj" fails.
  def test_a_cr_before_a_comment_or_ending_a_cdata_section_is_a_lone_cr
    assert_equal "i\n\nj", text_value("<a>i\r<!--c-->\nj</a>")
    assert_equal "k\n\nl", text_value("<a><![CDATA[k\r]]>\nl</a>")
  end

  # sabotage: add \t to TEXT_RUN's excluded set and answer a space for it
  # in text_special; the assert_equal on "m\tn" fails.
  def test_text_keeps_a_tab_and_an_lf
    assert_equal "m\tn", text_value("<a>m\tn</a>")
    assert_equal "o\np", text_value("<a>o\np</a>")
  end
end
