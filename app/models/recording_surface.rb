class RecordingSurface < ApplicationRecord
  belongs_to :recording, optional: true
  has_many :ingest_events, dependent: :destroy

  def self.normalize(artist_name, album_name, track_name)
    [
      artist_name,
      album_name,
      track_name
    ].map { |s|
      s.downcase.strip.gsub(/\s+/, " ")
    }.join("||")
  end

  def choose_release_candidate!(index)
    raise ArgumentError, "index required" if index.nil?

    candidates = release_candidates || []
    raise ArgumentError, "invalid index" unless candidates[index]

    update!(chosen_release_candidate_index: index)
  end

  def chosen_release_candidate
    return nil if chosen_release_candidate_index.nil?
    release_candidates[chosen_release_candidate_index]
  end
end
