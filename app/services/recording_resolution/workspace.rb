module RecordingResolution
  class Workspace
    PAGE = 30
    REVIEW_CANDIDATES = 3
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
      observations.where(lastfm_account_id: observation.lastfm_account_id)
        .where("#{Ledger::EXACT_KEY_SQL} = resolution_surface_key(CAST(? AS text), CAST(? AS text), CAST(? AS text))", artist, album, track)
        .where(<<~SQL, artist, album, track)
        (payload->>'artist_name', payload->>'album_name', payload->>'track_name')
          IS NOT DISTINCT FROM (CAST(? AS text), CAST(? AS text), CAST(? AS text))
      SQL
    end

    def surface(observation)
      artist, album, track = observation.payload.values_at(*Ledger::PAYLOAD_FIELDS)
      Surface.find_by(lastfm_account_id: observation.lastfm_account_id, artist:, album:, track:)
    end

    def matching_page(observation, before_id:)
      matches = matching(observation)
      page = ListeningPage.chronological(matches, before: before_id.presence).limit(PAGE + 1)
      [ page.pluck(:id), matches.count ]
    end

    def list(filter:, before_id:, before_count: 0)
      # Count effective unresolved observations before ranking their exact surfaces.
      prioritized = filter == "unresolved"
      plays = observations
      if prioritized
        accounts = listener.user_lastfm_accounts.active.joins(:user)
          .where(users: { disabled_at: nil, oidc_issuer: OidcClient::ISSUER }).where.not(users: { oidc_subject: [ nil, "" ] })
          .select(:lastfm_account_id)
        plays = Scrobble.where(lastfm_account_id: accounts).where.not(id: Ledger.assigned_observation_ids(listener, accounts))
      end
      grouped = plays.group("scrobbles.lastfm_account_id", *Ledger::PAYLOAD_FIELDS.map { |field| "payload->>'#{field}'" })
        .select("MIN(scrobbles.id) AS first_id", "COUNT(*) AS observation_count", "scrobbles.lastfm_account_id",
          "payload->>'artist_name' AS artist", "payload->>'album_name' AS album", "payload->>'track_name' AS track")
      if before_id.positive?
        grouped = if prioritized && before_count.positive?
          grouped.having("(COUNT(*), MIN(scrobbles.id)) < (?, ?)", before_count, before_id)
        else
          grouped.having("MIN(scrobbles.id) < ?", before_id)
        end
      end
      rows = Scrobble.from(grouped, :workspace_rows)
      rows = filter_surfaces(rows, filter) if filter && !prioritized
      order = prioritized ? "workspace_rows.observation_count DESC, workspace_rows.first_id DESC" : "workspace_rows.first_id DESC"
      page = rows.order(Arel.sql(order)).limit(PAGE + 1)
      return page.pluck(
        Arel.sql("workspace_rows.first_id"), Arel.sql("workspace_rows.artist"), Arel.sql("workspace_rows.album"),
        Arel.sql("workspace_rows.track"), Arel.sql("workspace_rows.observation_count")) unless prioritized

      # Status probes run only after limiting the grouped page.
      Scrobble.from(page.select("workspace_rows.*"), :workspace_rows).joins(<<~SQL).order(Arel.sql(order)).pluck(
        JOIN scrobbles queue_observation ON queue_observation.id = workspace_rows.first_id
        LEFT JOIN resolution_surfaces queue_surface ON queue_surface.lastfm_account_id = workspace_rows.lastfm_account_id
          AND queue_surface.exact_key = resolution_surface_key(workspace_rows.artist, workspace_rows.album, workspace_rows.track)
        CROSS JOIN LATERAL (
          SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb) AS claims
          FROM jsonb_each(queue_observation.payload::jsonb)
          WHERE key IN ('artist_mbid', 'album_mbid', 'track_mbid')
        ) observation_evidence
        LEFT JOIN LATERAL (
          SELECT ci.state, ci.failure FROM resolution_groups g JOIN catalog_imports ci
            ON ci.kind = 'recording_investigation' AND ci.entity_id = g.id
          WHERE g.surface_id = queue_surface.id AND g.claims = observation_evidence.claims ORDER BY ci.id DESC LIMIT 1
        ) investigation ON true
        LEFT JOIN LATERAL (
          SELECT a.evidence FROM resolution_groups g JOIN resolution_assessments a ON a.group_id = g.id
          WHERE g.surface_id = queue_surface.id AND g.claims = observation_evidence.claims
          ORDER BY (a.evidence->>'partial' IS NOT DISTINCT FROM 'true') ASC, a.id DESC LIMIT 1
        ) evidence ON true
      SQL
        Arel.sql("workspace_rows.first_id"), Arel.sql("workspace_rows.artist"), Arel.sql("workspace_rows.album"),
        Arel.sql("workspace_rows.track"), Arel.sql("workspace_rows.observation_count"),
        Arel.sql("investigation.state"), Arel.sql("investigation.failure"), Arel.sql("evidence.evidence::text")).map do |id, artist, album, track, count, state, failure, evidence|
        [ id, artist, album, track, count, review_action(state, failure, JSON.parse(evidence || "{}")) ]
      end
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

    private

    def review_action(state, failure, evidence)
      if state == "pending"
        return [ "Investigation requested", "Check investigation status" ]
      elsif state == "refreshing"
        return [ "Investigating", "Check investigation status" ]
      end

      count = evidence["ranking"]&.size || self.class.candidate_evidence(evidence).size
      return [ "Ambiguous", "Compare candidates" ] if count > 1
      return [ "Candidate found", "Review candidate evidence" ] if count == 1
      if failure.to_s.match?(/musicbrainz|discogs/i) || evidence["partial"] == true || state == "incomplete"
        return [ "Provider evidence incomplete", "Review evidence and retry" ]
      end
      return [ "Investigation failed", "Review investigation details" ] if state == "failed"
      return [ "No credible candidate", "Review search evidence" ] if state || evidence.present?

      [ "Uninvestigated", "Open to investigate" ]
    end

    def filter_surfaces(rows, filter)
      surfaces = Surface.from("resolution_surfaces workspace_surface")
        .where("workspace_surface.lastfm_account_id" => listener.user_lastfm_accounts.active.select(:lastfm_account_id))
        .select("workspace_surface.id", "workspace_surface.lastfm_account_id",
          "workspace_surface.artist", "workspace_surface.album", "workspace_surface.track")
      surfaces = surfaces.joins(head_join) if filter == "resolved"
      eligible = apply_filter(surfaces, filter)
      # Evaluate decisions on attached surfaces. Array equality matches NULL elements and supports a hash join.
      rows = rows.joins(<<~SQL)
        LEFT JOIN (#{eligible.to_sql} OFFSET 0) eligible_surface
          ON eligible_surface.lastfm_account_id = workspace_rows.lastfm_account_id
          AND ARRAY[eligible_surface.artist, eligible_surface.album, eligible_surface.track] =
            ARRAY[workspace_rows.artist, workspace_rows.album, workspace_rows.track]
      SQL
      rows.where("eligible_surface.id IS NOT NULL")
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
