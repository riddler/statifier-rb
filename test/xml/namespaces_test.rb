# frozen_string_literal: true

require "test_helper"
require_relative "xml_helper"

# Every element's namespace, resolved from the xmlns and xmlns:prefix
# declarations in scope as the reference's namespace scope resolves it
# (statifier-ex at the vendored tag, Statifier.Lowering.Namespace).
class NamespacesTest < Minitest::Test
  include XMLHelper

  # sabotage: make Scope#resolve answer nil for an unprefixed name; the
  # assert_equal on the root's namespace fails.
  def test_resolves_the_default_namespace_and_inherits_it
    element = root(%(<scxml xmlns="#{SCXML}"><state><final/></state></scxml>))
    state = element(element.children.first)

    assert_equal [SCXML, SCXML, SCXML], [element.namespace, state.namespace, state.children.first.namespace]
  end

  # sabotage: start the root under a scope whose default is SCXML instead of
  # Scope::EMPTY in open_tag; the assert_nil on the root fails.
  def test_reads_a_document_with_no_declaration_in_no_namespace
    element = root('<scxml version="1.0"><state id="a"/></scxml>')

    assert_nil element.namespace
    assert_nil element.children.first.namespace
  end

  # sabotage: make open_tag pass @stack.first&.scope (the root's scope)
  # instead of the parent's; the assert_equal on b's namespace fails.
  def test_scopes_a_declaration_to_its_elements_subtree
    element = root(%(<scxml xmlns="#{SCXML}"><a xmlns="urn:o"><b/></a><c/></scxml>))
    a = element(element.children.first)

    assert_equal ["urn:o", "urn:o", SCXML], [a.namespace, a.children.first.namespace, element.children.last.namespace]
  end

  # sabotage: make Scope#bind treat an empty value as undeclaring (answer
  # with(default: nil) for ""); the assert_equal on "" fails.
  def test_binds_the_empty_string_for_an_empty_declaration
    element = root(%(<scxml xmlns="#{SCXML}"><a xmlns=""><b/></a><c/></scxml>))
    a = element(element.children.first)

    assert_equal ["", "", SCXML], [a.namespace, a.children.first.namespace, element.children.last.namespace]
    prefixed = root('<a xmlns:p="urn:p"><p:b xmlns:p=""/><p:c/></a>')

    assert_equal ["", "urn:p"], prefixed.children.map(&:namespace)
  end

  # sabotage: resolve a prefixed name against the default namespace in
  # Scope#resolve; the assert_equal on the three children fails.
  def test_resolves_a_prefix_and_answers_nil_for_an_undeclared_one
    element = root(%(<s:scxml xmlns:s="#{SCXML}" xmlns="urn:d"><s:state/><x:y/><plain/></s:scxml>))

    assert_equal SCXML, element.namespace
    assert_equal [SCXML, nil, "urn:d"], element.children.map(&:namespace)
  end

  # sabotage: give elements inside <content> a fresh Scope::EMPTY (open_tag
  # passing Scope::EMPTY when the parent is named content); the assert_equal
  # on the inner scxml's namespace fails.
  def test_places_undeclared_markup_inside_content_in_the_enclosing_default_namespace
    inner_markup = '<scxml version="1.0"><final/></scxml>'
    source = %(<scxml xmlns="#{SCXML}"><state><invoke><content>#{inner_markup}</content></invoke></state></scxml>)
    inner = element(descend(root(source), 0, 0, 0, 0))

    assert_equal ["scxml", SCXML], [inner.name, inner.namespace]
    assert_equal inner_markup, inner.location.slice(source)
  end
end
