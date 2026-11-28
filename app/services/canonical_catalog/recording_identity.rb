module CanonicalCatalog
  class RecordingIdentity
    attr_reader :recording, :target, :aliases, :signature, :source_ids

    def initialize(assessment, mbid)
      evidence = assessment.evidence
      rows = RecordingResolution::Workspace.candidate_evidence(evidence)
      sources = rows.index_by { |row| row["id"] }
      (evidence["recording_publications"] || {}).each do |id, history|
        source = history["verified_recording"]
        sources[id] = (sources[id] || {}).merge(source) if source
      end
      editions = Array(evidence["construction_editions"]).filter_map do |data|
        next unless Edition.collection_context?(data)

        Edition.new(data, data.fetch("id"))
      rescue Store::Unverified
        nil
      end
      TrackComparison.corroborate_companion_editions(editions).each do |edition|
        edition.slots.each do |slot|
          source = slot.fetch(:recording)
          next if source["companion_edition_edits"].blank?

          id = source.fetch("id")
          current = sources[id] || source
          sources[id] = current.merge("companion_edition_edits" =>
            Array(current["companion_edition_edits"]) | source.fetch("companion_edition_edits"))
        end
      end
      chosen = sources[mbid]
      return unless chosen

      peers = sources.values.select do |source|
        Clients::Musicbrainz::MBID.match?(source["id"].to_s) &&
          TrackComparison.compare({ recording: chosen }, { recording: source }) == :equivalent
      end
      peers = [ chosen ] unless peers.combination(2).all? { |left, right| TrackComparison.compare({ recording: left }, { recording: right }) == :equivalent }
      heads = RecordingSourceDecision.heads(peers.pluck("id"))
      direct = Recording.where(mbid: peers.pluck("id")).index_by(&:mbid)
      current = peers.to_h { |source| [ source["id"], heads[source["id"]]&.recording || direct[source["id"]] ] }
      existing = current.values.compact.uniq
      @recording = current[mbid] || existing.first if current[mbid] || existing.one?
      @target = sources[@recording&.mbid] || peers.find { |source| TrackComparison.title_key(source["disambiguation"]) == "explicit" } || chosen
      @target = chosen if existing.many?
      @aliases = existing.many? ? [] : peers.reject { |source| current[source["id"]] || source["id"] == (@recording&.mbid || @target["id"]) }
      @source_ids = existing.many? ? [ mbid ] : peers.pluck("id")
      @signature = [ @target["id"], current.map { |id, record| [ id, record&.id, heads[id]&.id ] }.sort ]
    end

    def fingerprint
      Digest::SHA256.hexdigest(signature.to_json)
    end

    def apply!(assessment, user)
      record = recording || Store.recording!(target)
      aliases.each do |source|
        RecordingSourceDecision.revise!(source:, recording: record, expected_head: nil,
          actor: "listener:#{user.id}", reason: "Corroborated recording identity", assessment_id: assessment.id, compared_with: target)
      end
      record
    end
  end
end
