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
      matches = matching(observation).select("scrobbles.id", "COUNT(*) OVER () AS total")
      page = Scrobble.from(matches, :exact_matches).order(Arel.sql("exact_matches.id DESC")).limit(PAGE + 1)
      page = page.where("exact_matches.id < ?", before_id) if before_id.positive?
      rows = page.pluck(Arel.sql("exact_matches.id"), Arel.sql("exact_matches.total"))
      [ rows.map(&:first), rows.first&.last || (before_id.positive? ? matching(observation).count : 0) ]
    end

    def list(filter:, before_id:, before_count: 0)
      # Aggregate exact surfaces before examining their decisions or assessment evidence.
      grouped = observations.group("lastfm_account_id", *Ledger::PAYLOAD_FIELDS.map { |field| "payload->>'#{field}'" })
        .select("MIN(id) AS first_id", "COUNT(*) AS observation_count", "lastfm_account_id",
          "payload->>'artist_name' AS artist", "payload->>'album_name' AS album", "payload->>'track_name' AS track")
      prioritized = filter == "unresolved"
      if before_id.positive?
        grouped = if prioritized && before_count.positive?
          grouped.having("(COUNT(*), MIN(id)) < (?, ?)", before_count, before_id)
        else
          grouped.having("MIN(id) < ?", before_id)
        end
      end
      rows = Scrobble.from(grouped, :workspace_rows)
      rows = filter_surfaces(rows, filter) if filter
      order = prioritized ? "workspace_rows.observation_count DESC, workspace_rows.first_id DESC" : "workspace_rows.first_id DESC"
      page = rows.order(Arel.sql(order)).limit(PAGE + 1)
      return page.pluck(
        Arel.sql("workspace_rows.first_id"), Arel.sql("workspace_rows.artist"), Arel.sql("workspace_rows.album"),
        Arel.sql("workspace_rows.track"), Arel.sql("workspace_rows.observation_count")) unless prioritized

      # Status probes run only after limiting the grouped page.
      Scrobble.from(page.select("workspace_rows.*"), :workspace_rows).joins(<<~SQL).order(Arel.sql(order)).pluck(
        LEFT JOIN resolution_surfaces queue_surface ON queue_surface.lastfm_account_id = workspace_rows.lastfm_account_id
          AND queue_surface.exact_key = resolution_surface_key(workspace_rows.artist, workspace_rows.album, workspace_rows.track)
        LEFT JOIN LATERAL (
          SELECT ci.state FROM resolution_groups g JOIN catalog_imports ci
            ON ci.kind = 'recording_investigation' AND ci.entity_id = g.id
          WHERE g.surface_id = queue_surface.id ORDER BY ci.id DESC LIMIT 1
        ) investigation ON true
        LEFT JOIN LATERAL (
          SELECT true AS has_candidates FROM resolution_groups g JOIN resolution_assessments a ON a.group_id = g.id
          WHERE g.surface_id = queue_surface.id
            AND (jsonb_array_length(COALESCE(a.evidence->'ranking', a.evidence->'candidates', '[]')) > 0
              OR a.evidence->>'verified_recording' IS NOT NULL)
          LIMIT 1
        ) evidence ON true
      SQL
        Arel.sql("workspace_rows.first_id"), Arel.sql("workspace_rows.artist"), Arel.sql("workspace_rows.album"),
        Arel.sql("workspace_rows.track"), Arel.sql("workspace_rows.observation_count"),
        Arel.sql("investigation.state"), Arel.sql("evidence.has_candidates"))
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

    def filter_surfaces(rows, filter)
      surfaces = Surface.from("resolution_surfaces workspace_surface")
        .where("workspace_surface.lastfm_account_id" => listener.user_lastfm_accounts.active.select(:lastfm_account_id))
        .select("workspace_surface.id", "workspace_surface.lastfm_account_id",
          "workspace_surface.artist", "workspace_surface.album", "workspace_surface.track")
      resolved = %w[resolved unresolved].include?(filter)
      surfaces = surfaces.joins(head_join) if resolved
      eligible = apply_filter(surfaces, resolved ? "resolved" : filter)
      # Evaluate decisions on attached surfaces. Array equality matches NULL elements and supports a hash join.
      rows = rows.joins(<<~SQL)
        LEFT JOIN (#{eligible.to_sql} OFFSET 0) eligible_surface
          ON eligible_surface.lastfm_account_id = workspace_rows.lastfm_account_id
          AND ARRAY[eligible_surface.artist, eligible_surface.album, eligible_surface.track] =
            ARRAY[workspace_rows.artist, workspace_rows.album, workspace_rows.track]
      SQL
      filter == "unresolved" ? rows.where("eligible_surface.id IS NULL") : rows.where("eligible_surface.id IS NOT NULL")
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
