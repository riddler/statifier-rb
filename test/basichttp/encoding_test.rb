# frozen_string_literal: true

require "test_helper"
require "statifier/basichttp"

# Statifier::BasicHTTP::Encoding: a value written as text, a float's
# spelling, the form and key-field escapes and the form decoder, each as a
# table of rows the reference's processor answers alike.
class BasicHTTPEncodingTest < Minitest::Test
  ENC = Statifier::BasicHTTP::Encoding
  U = Predicator::UNDEFINED
  CAFE = "caf\u00e9"

  # A value written as text: [value, text].
  VALUES = [
    ["two words", "two words"],
    ["", ""],
    [nil, "null"],
    [U, ""],
    [true, "true"],
    [false, "false"],
    [0, "0"],
    [-7, "-7"],
    [12_345_678_901_234_567_890, "12345678901234567890"],
    [1.5, "1.5"],
    [[1, 2], "[1,2]"],
    [[], "[]"],
    [{}, "{}"],
    [["s", 2, 1.5, true, nil, [], {}], '["s",2,1.5,true,null,[],{}]'],
    [[U, "x"], '[null,"x"]'],
    [{ "a" => { "b" => U } }, '{"a":{"b":null}}'],
    [{ "z" => 2, "\u00e9" => 1, "A" => 3 }, "{\"A\":3,\"z\":2,\"\u00e9\":1}"],
    [{ "q" => "\"\\\n\t\b\f\r\u0001\u001f\u007f\u2028/" },
     "{\"q\":\"\\\"\\\\\\n\\t\\b\\f\\r\\u0001\\u001F\u007f\u2028/\"}"],
    [[[[1]]], "[[[1]]]"],
    [Predicator::Date.new(year: 2026, month: 1, day: 2), '{"$type":"date","value":"2026-01-02"}'],
    [[Predicator::Date.new(year: 2026, month: 1, day: 2)], '[{"$type":"date","value":"2026-01-02"}]'],
    [["caf\xE9".b], ""],
    [{ 1 => "a" }, ""],
    [:symbol, ""]
  ].freeze

  # sabotage: drop `.sort_by(&:b)` in json_map; the key-order row fails.
  def test_a_value_is_written_as_the_reference_writes_it
    VALUES.each do |value, text|
      assert_equal text, ENC.value(value), value.inspect
    end
  end

  # sabotage: drop the depth check in json; the deep list is written as JSON text.
  def test_a_list_nested_past_the_json_depth_is_not_json_text
    deep = (1..ENC::JSON_DEPTH).reduce(1) { |inner, _| [inner] }

    assert_equal "", ENC.value(deep)
    assert ENC.value(deep[0]).start_with?("[[")
  end

  # A float's spelling: [float, text].
  FLOATS = [
    [2.0, "2.0"], [1.5, "1.5"], [0.1, "0.1"], [100.0, "100.0"], [0.0001, "0.0001"], [1.0e15, "1.0e15"],
    [1.0e-7, "1.0e-7"], [9_007_199_254_740_992.0, "9.007199254740992e15"],
    [123_456_789_012_345_680.0, "1.2345678901234568e17"],
    [2.5e-300, "2.5e-300"], [0.0, "0.0"], [-0.0, "-0.0"], [-1.5, "-1.5"], [1234.5, "1234.5"], [1.0e21, "1.0e21"]
  ].freeze

  # sabotage: drop the EXPONENT_FROM return in float; the 2**53 row is written plain.
  def test_a_float_is_written_in_the_reference_spelling
    FLOATS.each { |number, text| assert_equal text, ENC.float(number), number.inspect }
  end

  # sabotage: write a space as %20 in www_form; the form row fails.
  def test_a_form_escapes_every_byte_outside_the_unreserved_set_and_writes_a_space_as_plus
    assert_equal "_scxmleventname=ping&name=two+words+~%2A%2F%26%3D%2B", ENC.form([%w[_scxmleventname ping],
                                                                                   ["name", "two words ~*/&=+"]])
    assert_equal "n=caf%C3%A9", ENC.form([["n", CAFE]])
    assert_equal "", ENC.form([])
  end

  # sabotage: write a space as + in field; the key field row fails.
  def test_a_key_field_escapes_every_byte_outside_the_unreserved_set
    assert_equal "a%2Fb%20c", ENC.field("a/b c")
    assert_equal "caf%C3%A9", ENC.field(CAFE)
  end

  # A form or query string decoded: [text, pairs].
  PAIRS = [
    ["a=1&b=2", [%w[a 1], %w[b 2]]],
    ["", []],
    ["&", [["", ""]]],
    ["a&", [["a", ""]]],
    ["a&&b=&=c", [["a", ""], ["", ""], ["b", ""], ["", "c"]]],
    ["a=b=c", [%w[a b=c]]],
    ["s=hi+there%21", [["s", "hi there!"]]],
    ["%zz=1%2", [%w[%zz 1%2]]],
    ["n=caf%C3%A9", [["n", CAFE]]],
    ["a=%E9", nil],
    ["%E9=1", nil]
  ].freeze

  # sabotage: split each pair at its last `=` in pairs (rpartition); the a=b=c row fails.
  def test_a_form_is_decoded_as_the_reference_decodes_one
    PAIRS.each do |text, pairs|
      pairs.nil? ? assert_nil(ENC.pairs(text), text) : assert_equal(pairs, ENC.pairs(text), text)
    end
  end

  # sabotage: read `+` as a space in unfield; the plus row fails.
  def test_a_key_field_decodes_its_escapes_and_keeps_a_plus
    assert_equal "a/b c+", ENC.unfield("a%2Fb%20c+")
    assert_nil ENC.unfield("%E9")
  end
end
