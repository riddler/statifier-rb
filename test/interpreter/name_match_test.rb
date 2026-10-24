# frozen_string_literal: true

require "test_helper"

# The event-name matcher of the specification's section 3.13: a table of
# descriptors (as an `event` attribute is written) against event names, the
# reference's own cases first.
class NameMatchTest < Minitest::Test
  N = Internals::Interpreter::NameMatch

  # [descriptors as written, event name, whether they match]
  TABLE = [
    ["error.execution", "error.execution", true],
    ["error", "error.execution", true],
    ["error", "errors.execution", false],
    ["foo.*", "foo", true],
    ["foo.*", "foo.bar", true],
    ["foo.", "foo", true],
    ["foo.", "foo.bar", true],
    ["*", "foo", true],
    ["*", "foo.bar", true],
    ["foo *", "bar", true],
    ["foo.bar", "foo", false],
    ["foo", "foo", true],
    ["foo", "foobar", false],
    ["foo bar", "bar.baz", true],
    ["foo bar", "baz", false],
    ["foo.*.bar", "foo.x.bar", false],
    ["foo.*.bar", "foo.*.bar", true],
    ["foo.bar.*", "foo.bar.baz.qux", true],
    ["foo.bar.*", "foo.baz", false],
    ["*", "", true],
    ["e.go", "e.go.now", true],
    ["e.go", "e", false]
  ].freeze

  # The descriptors of an `event` attribute, split as the compiler splits
  # them.
  def descriptors(written) = written.split.map { _1.split(".", -1) }

  # sabotage: compare event_tokens == normalized (no prefix) in
  # NameMatch.descriptor_match?; the assert_equal on the table fails at
  # "error" against "error.execution".
  # sabotage: drop the "" clause from NameMatch.normalize; the assert_equal
  # on the table fails at "foo." against "foo".
  # sabotage: use all? in place of any? in NameMatch.name_match?; the
  # assert_equal on the table fails at "foo *" against "bar".
  def test_the_table_of_descriptors_and_names
    TABLE.each do |written, name, expected|
      matched = N.name_match?(descriptors(written), N.tokenize(name))

      assert_equal expected, matched, "#{written.inspect} on #{name.inspect}"
    end
  end

  # sabotage: split without the -1 limit in NameMatch.tokenize; the
  # assert_equal on "a." fails.
  def test_tokenize_keeps_every_empty_part
    tokens = ["error.execution", "foo", "a.", ""].map { N.tokenize(_1) }

    assert_equal [%w[error execution], ["foo"], ["a", ""], [""]], tokens
  end

  # sabotage: answer descriptor in place of descriptor[0...-1] in
  # NameMatch.normalize; the assert_equal on the trailing star fails.
  def test_a_trailing_star_or_dot_is_dropped_and_an_inner_star_is_kept
    normalized = [%w[foo *], ["foo", ""], ["*"], %w[foo * bar]].map { N.normalize(_1) }

    assert_equal [["foo"], ["foo"], [], %w[foo * bar]], normalized
  end
end
