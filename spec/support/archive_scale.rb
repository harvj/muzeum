module ArchiveScale
  SIZE = 293_000

  def seed_archive_at_scale(user)
    account_id = user.source_account.id
    Scrobble.connection.execute(<<~SQL)
      INSERT INTO scrobbles (user_id, lastfm_account_id, played_at, payload, created_at, updated_at)
      SELECT #{user.id}, #{account_id}, TIMESTAMP '2026-01-01' - ((n + 1) / 2) * INTERVAL '1 minute',
        jsonb_build_object('artist_name', 'Artist ' || (n % 1800), 'album_name', 'Album ' || (n % 8400),
          'track_name', 'Track ' || (n % 58000)),
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM generate_series(0, #{SIZE - 1}) AS n
    SQL
  end
end
