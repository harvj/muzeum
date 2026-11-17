module RecordingResolution
  class Ledger
    VERSION = "exact-surface-v1"
    PAYLOAD_FIELDS = %w[artist_name album_name track_name].freeze

    def self.attach!(scrobble)
      artist, album, track = scrobble.payload.values_at(*PAYLOAD_FIELDS)
      key = Surface.connection.select_value(
        Surface.sanitize_sql_array([ "SELECT resolution_surface_key(?, ?, ?)", artist, album, track ])
      )
      surface = Surface.find_by(lastfm_account_id: scrobble.lastfm_account_id, exact_key: key) ||
        Surface.create_or_find_by!(lastfm_account_id: scrobble.lastfm_account_id, artist:, album:, track:)
      unless [ surface.artist, surface.album, surface.track ] == [ artist, album, track ]
        raise ArgumentError, "Exact surface digest collision"
      end

      Membership.find_by(scrobble_id: scrobble.id) ||
        Membership.create_or_find_by!(scrobble_id: scrobble.id, surface_id: surface.id)
      surface
    end

    # The caller supplies the authenticated listener. Scope and author come from that identity.
    def self.record!(listener:, scrobble:, scope:, mode:, reason:, recording: nil, assessment: nil, expected_head: nil)
      raise ArgumentError, "Invalid listener decision scope" unless %i[surface scrobble].include?(scope)
      raise ArgumentError, "A reason is required" if reason.blank?

      Decision.transaction do
        user = User.lock.find(listener.id)
        raise ActiveRecord::RecordNotFound unless user.login_enabled?

        user.user_lastfm_accounts.active.lock.find_by!(lastfm_account_id: scrobble.lastfm_account_id)
        surface = attach!(scrobble)
        surface.lock!
        stream = Decision.where(surface_id: surface.id, user_id: user.id,
          scrobble_id: scope == :scrobble ? scrobble.id : nil)
        head = stream.order(id: :desc).first
        raise ActiveRecord::StaleObjectError.new(head || surface, "append decision") unless head&.id == expected_head

        stream.create!(mode:, reason:, recording_id: recording&.id, assessment_id: assessment&.id,
          predecessor_id: head&.id, actor: "listener", version: VERSION,
          evidence: { "observation_id" => scrobble.id })
      end
    end

    def self.assessments(listener)
      Assessment.where(group_id: Group.where(surface_id: visible_surfaces(listener)).select(:id))
    end

    def self.history(listener)
      Decision.where(surface_id: visible_surfaces(listener), user_id: [ nil, listener.id ])
    end

    def self.visible_surfaces(listener)
      grants = UserLastfmAccount.active.where(user_id: listener.id).joins(:user)
        .where(users: { disabled_at: nil, oidc_issuer: OidcClient::ISSUER })
        .where.not(users: { oidc_subject: [ nil, "" ] })
      Surface.where(lastfm_account_id: grants.select(:lastfm_account_id)).select(:id)
    end
    private_class_method :visible_surfaces

    # Keep archive authorization in the query so a previously constructed relation observes revocation.
    def self.effective(listener)
      return Scrobble.none unless listener.id

      join = Scrobble.sanitize_sql_array([ <<~SQL, { listener: listener.id, issuer: OidcClient::ISSUER } ])
        JOIN user_lastfm_accounts resolution_grant
          ON resolution_grant.lastfm_account_id = scrobbles.lastfm_account_id
          AND resolution_grant.user_id = :listener AND resolution_grant.revoked_at IS NULL
        JOIN users resolution_listener ON resolution_listener.id = resolution_grant.user_id
          AND resolution_listener.disabled_at IS NULL AND resolution_listener.oidc_issuer = :issuer
          AND resolution_listener.oidc_subject IS NOT NULL AND resolution_listener.oidc_subject <> ''
        LEFT JOIN resolution_surfaces exact_surface ON exact_surface.lastfm_account_id = scrobbles.lastfm_account_id
          AND exact_surface.exact_key = resolution_surface_key(
            scrobbles.payload->>'artist_name', scrobbles.payload->>'album_name', scrobbles.payload->>'track_name')
          AND (exact_surface.artist, exact_surface.album, exact_surface.track) IS NOT DISTINCT FROM
            (scrobbles.payload->>'artist_name', scrobbles.payload->>'album_name', scrobbles.payload->>'track_name')
        LEFT JOIN LATERAL (
          SELECT id, mode, recording_id FROM (
            (SELECT id, mode, recording_id, 1 AS priority FROM resolution_decisions
             WHERE surface_id = exact_surface.id AND user_id = :listener AND scrobble_id = scrobbles.id
             ORDER BY id DESC LIMIT 1)
            UNION ALL
            (SELECT id, mode, recording_id, 2 AS priority FROM resolution_decisions
             WHERE surface_id = exact_surface.id AND user_id = :listener AND scrobble_id IS NULL
             ORDER BY id DESC LIMIT 1)
            UNION ALL
            (SELECT id, mode, recording_id, 3 AS priority FROM resolution_decisions
             WHERE surface_id = exact_surface.id AND user_id IS NULL AND scrobble_id IS NULL
             ORDER BY id DESC LIMIT 1)
          ) heads WHERE mode <> 'inherit' ORDER BY priority LIMIT 1
        ) effective_resolution ON true
      SQL
      Scrobble.joins(join).select("scrobbles.*, effective_resolution.recording_id AS effective_recording_id, " \
        "effective_resolution.id AS effective_recording_decision_id, effective_resolution.mode AS effective_recording_mode")
    end
  end
end
