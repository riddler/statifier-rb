# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# The five predefined entities and decimal and hex character references, in
# text and in attribute values.
class ReferencesTest < Minitest::Test
  include XMLHelper

  ENTITIES = { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => '"', "&apos;" => "'" }.freeze

  CHARACTERS = {
    "&#65;" => "A", "&#x41;" => "A", "&#x6c;" => "l", "&#x4A;" => "J",
    "&#x1F4DA;" => "\u{1F4DA}", "&#128218;" => "\u{1F4DA}", "&#00065;" => "A"
  }.freeze

  # sabotage: drop "apos" from CharacterData::PREDEFINED; the parse of the
  # &apos; source is refused and root flunks.
  def test_expands_the_five_predefined_entities_in_text_and_in_an_attribute_value
    ENTITIES.each do |reference, character|
      element = root(%(<a x="#{reference}">#{reference}</a>))

      assert_equal [character, character], [element.attributes.first.value, text(element.children.first).value],
                   reference
    end
  end

  # sabotage: read every character reference as decimal in
  # character_reference (drop the HEX branch); the assert_equal for &#x41;
  # fails.
  def test_decodes_decimal_and_hex_character_references
    CHARACTERS.each do |reference, character|
      assert_equal character, text_value("<a>#{reference}</a>"), reference
      assert_equal character, attribute_value(%(<a x="#{reference}"/>)), reference
    end
  end

  # sabotage: refuse every non-predefined name in entity_reference (drop
  # its first line); root flunks on the parse of the declared entity.
  def test_keeps_a_declared_entity_reference_as_its_literal_text
    assert_equal "&x;", text_value(%(<!DOCTYPE a [<!ENTITY x "y">]><a>&x;</a>))
  end

  # sabotage: expand the reference to an empty string in entity_reference
  # (return "" instead of "&#{body};"); the assert_equal on "&x;" fails.
  def test_keeps_an_entity_reference_in_an_attribute_value_as_its_literal_text
    assert_equal "&x;", attribute_value(%(<!DOCTYPE a [<!ENTITY x "y">]><a b="&x;"/>))
  end

  # sabotage: set @doctype in skip_doctype only when the declaration holds
  # a "[" (@cursor.text.byteslice(start.offset, angle - start.offset)
  # .include?("[")); root flunks on the external-subset document.
  def test_keeps_a_reference_under_an_external_subset_as_its_literal_text
    assert_equal "t &foo; & A", text_value(%(<!DOCTYPE a SYSTEM "x.dtd"><a>t &foo; &amp; &#65;</a>))
  end
end
