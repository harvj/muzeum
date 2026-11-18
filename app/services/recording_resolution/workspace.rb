module RecordingResolution
  class Workspace
    PAGE = 30
    FILTERS = %w[unresolved suggested ambiguous resolved exceptions].freeze

    attr_reader :listener

    def initialize(listener)
      @listener = listener
    end

    def observations
      Scrobble.where(lastfm_account_id: listener.user_lastfm_accounts.active.select(:lastfm_account_id))
    end

    def matching(observation)
      artist, album, track = observation.payload.values_at(*Ledger::PAYLOAD_FIELDS)
      observations.where(lastfm_account_id: observation.lastfm_account_id).where(<<~SQL, artist, album, track)
        (payload->>'artist_name', payload->>'album_name', payload->>'track_name')
          IS NOT DISTINCT FROM (CAST(? AS text), CAST(? AS text), CAST(? AS text))
      SQL
    end

    def surface(observation)
      artist, album, track = observation.payload.values_at(*Ledger::PAYLOAD_FIELDS)
      Surface.find_by(lastfm_account_id: observation.lastfm_account_id, artist:, album:, track:)
    end

    def list(filter:, before_id:)
      # The earliest observation identifies a surface; new matching observations do not move it between pages.
      scoped = observations.joins(surface_join).joins(head_join)
      scoped = apply_filter(scoped, filter)
      rows = scoped.group("scrobbles.lastfm_account_id", "scrobbles.payload->>'artist_name'",
        "scrobbles.payload->>'album_name'", "scrobbles.payload->>'track_name'")
      rows = rows.having("MIN(scrobbles.id) < ?", before_id) if before_id.positive?
      rows.order(Arel.sql("MIN(scrobbles.id) DESC")).limit(PAGE + 1).pluck(
        Arel.sql("min(scrobbles.id)"), Arel.sql("payload->>'artist_name'"), Arel.sql("payload->>'album_name'"),
        Arel.sql("payload->>'track_name'"), Arel.sql("count(*)"))
    end

    def assessments(surface)
      Ledger.assessments(listener).where(group_id: Group.where(surface_id: surface&.id)).order(id: :desc)
    end

    def history(surface)
      Ledger.history(listener).where(surface_id: surface&.id).order(id: :desc)
    end

    def self.candidates(assessment)
      candidate_evidence(assessment&.evidence || {})
    end

    def self.candidate_evidence(evidence)
      [ evidence["verified_recording"], *Array(evidence["candidates"]) ].compact
        .select { |item| Clients::Musicbrainz::MBID.match?(item["id"].to_s) && item["title"].present? }
        .uniq { |item| item["id"] }
    end

    def self.editions(candidate, assessment)
      appearances = Array(candidate["releases"]).filter_map do |release|
        [ release["title"], release["id"] ] if release["title"].present? && Clients::Musicbrainz::MBID.match?(release["id"].to_s)
      end
      edition = assessment.evidence["edition"]
      if edition && Array(assessment.evidence["slots"]).any? { |slot| slot["recording_mbid"] == candidate["id"] }
        appearances.unshift([ edition["title"], edition["id"] ])
      end
      appearances.uniq(&:last).first(25)
    end

    private

    def surface_join
      <<~SQL
        LEFT JOIN resolution_surfaces workspace_surface ON workspace_surface.lastfm_account_id = scrobbles.lastfm_account_id
          AND workspace_surface.exact_key = resolution_surface_key(
            scrobbles.payload->>'artist_name', scrobbles.payload->>'album_name', scrobbles.payload->>'track_name')
          AND (workspace_surface.artist, workspace_surface.album, workspace_surface.track) IS NOT DISTINCT FROM
            (scrobbles.payload->>'artist_name', scrobbles.payload->>'album_name', scrobbles.payload->>'track_name')
      SQL
    end

    def head_join
      Scrobble.sanitize_sql_array([ <<~SQL, { user: listener.id } ])
        LEFT JOIN LATERAL (
          SELECT mode FROM resolution_decisions
          WHERE surface_id = workspace_surface.id AND user_id = :user AND scrobble_id IS NULL
          ORDER BY id DESC LIMIT 1
        ) workspace_head ON true
        LEFT JOIN LATERAL (
          SELECT mode FROM resolution_decisions
          WHERE surface_id = workspace_surface.id AND user_id IS NULL AND scrobble_id IS NULL
          ORDER BY id DESC LIMIT 1
        ) workspace_auto ON true
      SQL
    end

    def apply_filter(scoped, filter)
      mode = "COALESCE(NULLIF(workspace_head.mode, 'inherit'), workspace_auto.mode, 'unresolved')"
      case filter
      when "resolved" then scoped.where("#{mode} = 'resolved'")
      when "unresolved" then scoped.where("#{mode} <> 'resolved'")
      when "suggested", "ambiguous"
        predicate = filter == "suggested" ?
          "a.evidence->>'suggested_mbid' IS NOT NULL OR a.evidence->>'review_mbid' IS NOT NULL OR a.suggested_recording_id IS NOT NULL" :
          "a.evidence->'reasons' ?| ARRAY['competing_recordings', 'discogs_disagreement', 'source_identity_conflict']"
        scoped.where(<<~SQL)
          EXISTS (SELECT 1 FROM resolution_groups g JOIN resolution_assessments a ON a.group_id = g.id
            WHERE g.surface_id = workspace_surface.id AND (#{predicate}))
        SQL
      when "exceptions"
        scoped.where(<<~SQL, listener.id)
          EXISTS (SELECT 1 FROM resolution_decisions d
            WHERE d.surface_id = workspace_surface.id AND d.user_id = ? AND d.scrobble_id IS NOT NULL
            AND d.mode <> 'inherit' AND NOT EXISTS (SELECT 1 FROM resolution_decisions successor WHERE successor.predecessor_id = d.id))
        SQL
      else scoped
      end
    end
  end
end
