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
end
