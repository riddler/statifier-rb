# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require_relative "datamodel_helper"

# Datamodel::Stores: each store's root read from the instruction list, and
# the list rewritten with its jumps moved.
class StoresTest < Minitest::Test
  include DatamodelHelper

  S = D::Stores

  # sabotage: search for depths[before] < depths[at] - count - 1 in
  # Stores.roots; the assert_equal on the roots fails.
  def test_each_store_names_the_root_its_target_begins_with
    instructions = Predicator.compile_program!("a.b[c + 1] = 2; while (d < 1) { e = f[0] }; g = h or i")
    stores = instructions.each_index.select { instructions[_1].first == "store" }

    assert_equal stores.zip(%w[a e g]).to_h, S.roots(instructions)
  end

  # sabotage: give pop_jump_if_falsy's taken edge the depth unchanged in
  # Stores.successors; the assert_equal on the depths fails.
  def test_the_depth_before_each_instruction_follows_every_jump
    instructions = Predicator.compile_program!("if (x) { y = 1 } else { y = 2 }")

    assert_equal [0, 1, 0, 1, 2, 0, 0, 1, 2], S.depths(instructions)
  end

  # sabotage: answer the store unchanged for a protected root in Stores.piece;
  # the assert_equal on the rewritten list fails.
  def test_a_protected_store_becomes_the_guard_and_another_is_noted
    rewritten = S.guarded(Predicator.compile_program!("x = 1; _event = 2"), ["_event"])
    expected = [%w[lit x], ["lit", 1], ["store", 1], %w[lit x], %w[load x], ["call", S::NOTE, 2], ["pop"],
                %w[lit _event], ["lit", 2], %w[lit _event], ["call", S::GUARD, 1]]

    assert_equal expected, rewritten
  end

  # sabotage: move a jump by its old offset (answer [[opcode, offset]]) in
  # Stores.relocated; the assert_equal on the offsets fails.
  def test_every_jump_lands_where_it_landed_before
    rewritten = S.guarded(Predicator.compile_program!("while (x < 3) { x = x + 1 }"), [])

    assert_equal([["pop_jump_if_falsy", 11], ["jump_backward", 13]], rewritten.select { S::JUMPS.key?(_1.first) })
    assert_equal({ "x" => 3 }, Predicator.execute!(rewritten, { "x" => 0 }, functions: { S::NOTE => ->(_r, _v) {} }))
  end

  # sabotage: answer [instruction] for a nil root in Stores.piece; the
  # assert_equal on the rewritten list fails.
  def test_a_store_whose_root_cannot_be_read_becomes_a_refusal
    instructions = [%w[load r], ["lit", 1], ["store", 1]]

    assert_equal({ 2 => nil }, S.roots(instructions))
    assert_equal [%w[load r], ["lit", 1], ["call", S::UNREAD, 0]], S.guarded(instructions, ["r"])
  end

  # sabotage: drop the UNREAD function from Program.functions; the
  # assert_equal on the reason fails, as the call names an unknown function.
  def test_a_store_whose_root_cannot_be_read_fails_the_run_and_writes_nothing
    instructions = [%w[lit r], %w[load r], ["lit", 1], ["store", 1]]
    unread = Internals::Machine::Program.new(instructions:, source: "s")
    executed = D.execute(context({ "r" => "x" }), unread)

    assert_includes executed.error.error.reason, "statifier:unread() raised"
    assert_equal "x", executed.data["r"]
  end

  # Every instruction of instruction-set version 6 with the depth it moves
  # by: nil where an operand gives it, :jump for a jump.
  ISA6 = {
    "lit" => 1, "load" => 1, "object_new" => 1, "duration" => 1, "pop" => -1, "compare" => -1, "add" => -1,
    "subtract" => -1, "multiply" => -1, "divide" => -1, "modulo" => -1, "bracket_access" => -1, "in" => -1,
    "contains" => -1, "object_set" => -1, "not" => 0, "unary_bang" => 0, "unary_minus" => 0, "access" => 0,
    "relative_date" => 0, "cast" => 0, "make_list" => nil, "call" => nil, "store" => nil, "jump" => :jump,
    "pop_jump_if_falsy" => :jump, "jump_if_falsy_or_pop" => :jump, "jump_if_true_or_pop" => :jump,
    "jump_backward" => :jump
  }.freeze

  # sabotage: drop "cast" => 0 from Stores::EFFECTS; the assert_equal on the
  # table fails.
  def test_every_instruction_of_the_version_has_its_effect
    table = S::OPCODES.to_h { [_1, S::JUMPS.key?(_1) ? :jump : S::EFFECTS[_1]] }

    assert_equal [6, ISA6], [S::ISA_VERSION, table]
    assert_equal({ 3 => "x" }, S.roots(Predicator.compile_program!("x = y::integer")).select { _2 })
  end

  # sabotage: drop the OPCODES check from Stores.readable? and give an
  # unlisted instruction effect 0 (EFFECTS.fetch(opcode, 0)) in
  # Stores.effect; the assert_equal fails, as the store into _event is read
  # as a store into "a".
  def test_an_instruction_the_table_does_not_list_leaves_no_store_read
    instructions = [%w[lit _event], %w[lit a], %w[lit a], ["make_list", 1], ["mystery"], ["store", 1]]

    assert_equal({ 5 => nil }, S.roots(instructions))
    assert_equal ["call", S::UNREAD, 0], S.guarded(instructions, ["_event"]).last
  end

  # sabotage: drop "Predicator.isa_version == ISA_VERSION &&" from
  # Stores.readable?; the assert_equal fails, as the store is read.
  def test_another_instruction_set_version_leaves_no_store_read
    instructions = Predicator.compile_program!("x = 1")

    Predicator.stub(:isa_version, 7) { assert_equal({ 2 => nil }, S.roots(instructions)) }
  end
end
