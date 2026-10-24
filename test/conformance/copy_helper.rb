# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "corpus"

module Conformance
  # A throwaway copy of conformance/ for the tests that must break a file to
  # show a check refuses it: the vendored files and the shipped registry are
  # never edited, so each such test edits a copy and the copy is removed.
  module CopyHelper
    def with_conformance_copy
      Dir.mktmpdir("conformance") do |tmp|
        dir = File.join(tmp, "conformance")
        FileUtils.cp_r(ROOT, dir)
        yield dir
      end
    end

    # Rewrites the file at relative under dir through the block, which takes
    # and answers its bytes.
    def rewrite(dir, relative)
      path = File.join(dir, relative)
      File.binwrite(path, yield(File.binread(path)))
    end

    # Rewrites the JSON file at relative under dir through the block, which
    # takes the parsed value and may change it in place.
    def rewrite_json(dir, relative)
      rewrite(dir, relative) do |bytes|
        value = JSON.parse(bytes)
        yield value
        JSON.generate(value)
      end
    end
  end
end
