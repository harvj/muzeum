module RecordingResolution
  module DecisionReasons
    DEFAULTS = {
      "resolved" => "confirmed_candidate",
      "unresolved" => "left_unresolved",
      "inherit" => "restore_inheritance"
    }.freeze

    OPTIONS = {
      "resolved" => {
        "confirmed_candidate" => "Confirmed candidate",
        "verified_identifier" => "Verified recording identifier",
        "corroborating_evidence" => "Corroborating catalog evidence",
        "personally_verified" => "I verified the recording",
        "correction" => "Correct a previous assignment"
      }.freeze,
      "unresolved" => {
        "left_unresolved" => "Left unresolved",
        "insufficient_evidence" => "Insufficient evidence",
        "multiple_candidates" => "Multiple plausible candidates",
        "inaccurate_claims" => "Inaccurate source claims"
      }.freeze,
      "inherit" => { "restore_inheritance" => "Return to inherited resolution" }.freeze
    }.freeze
  end
end
