class ReleaseTrackListeningDecision < ApplicationRecord
  belongs_to :user
  belongs_to :release
  belongs_to :recording

  def self.included_memberships(user, release_ids)
    preferences = where(user:, release_id: release_ids).select("DISTINCT ON (release_id, recording_id) release_id, recording_id, included")
      .order(:release_id, :recording_id, id: :desc)
    CatalogTrackSlot.where(release_id: release_ids)
      .joins(<<~SQL)
        LEFT JOIN (#{preferences.to_sql}) track_preference
          ON track_preference.release_id = catalog_track_slots.release_id
          AND track_preference.recording_id = catalog_track_slots.recording_id
      SQL
      .where("(catalog_track_slots.edition_mbid IS NULL OR track_preference.included = TRUE)")
      .distinct
  end
end
