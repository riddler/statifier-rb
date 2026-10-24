# frozen_string_literal: true

require_relative "corpus"

module Conformance
  # THE SEAM: what the run does with one case. It is the one place the
  # library is plugged into the run; the runner, the registry check and the
  # ratchet all reach the library through Drive.call and nothing else.
  #
  # A drive takes a case (one element of a suite file's cases, as the JSON
  # parser gives it) and answers :pass, or a String saying why the case
  # failed. Anything other than :pass is a fail, and a drive that raises is a
  # fail naming the exception: a case is never skipped and never aborts the
  # run.
  #
  # This package has no driver yet, so the drive answers every case with the
  # same reason and the run passes nothing. The change that brings it
  # replaces the body of Drive.call with the drive
  # the copy's RATCHET.md describes under "What a case asserts": compile the
  # case's source, start it and compare the active leaf states with
  # initial_configuration, then send each step's event and compare with the
  # step's configuration (and, for a case with a host object or a stated
  # position, what RATCHET.md says the runner honours there).
  module Drive
    # The reason every case fails while nothing drives it.
    NOT_DRIVEN = "not driven: this package has no driver yet"

    # The answer for item: :pass, or the reason it failed.
    def self.call(_item) = NOT_DRIVEN
  end

  # The run: every case of every suite, each answered pass or fail. There is
  # no skip list and no third result.
  module Runner
    # The results of one run over corpus, by case id in corpus order: each
    # {"result" => "pass"} or {"result" => "fail", "reason" => ...}. drive is
    # anything answering call(item) as Drive does.
    def self.run(corpus, drive: Drive)
      corpus.cases.to_h { |item| [item.fetch("id"), result_for(item, drive)] }
    end

    def self.result_for(item, drive)
      answer = drive.call(item)
      return { "result" => "pass" } if answer == :pass

      { "result" => "fail", "reason" => answer.to_s }
    rescue StandardError => e
      { "result" => "fail", "reason" => "raised #{e.class}: #{e.message}" }
    end
    private_class_method :result_for

    # One line per suite: how many of its cases this package's registry
    # (entries, its entries) does not claim, and how many of those the
    # reference's registry (reference, its entries) claims.
    def self.unclaimed_lines(corpus, entries, reference)
      claimed = entries.to_h { |entry| [entry["case_id"], true] }
      theirs = reference.to_h { |entry| [entry["case_id"], true] }
      corpus.suites.map { |suite| unclaimed_line(suite, claimed, theirs) }
    end

    def self.unclaimed_line(suite, claimed, theirs)
      open = suite["cases"].map { |item| item["id"] }.reject { |id| claimed.key?(id) }
      "conformance: #{suite["suite"]}: #{open.size} of #{suite["cases"].size} cases not yet claimed " \
        "(the reference claims #{open.count { |id| theirs.key?(id) }} of them)"
    end
    private_class_method :unclaimed_line
  end
end
