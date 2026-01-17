class RecordingSurface < ApplicationRecord
  belongs_to :recording

  def self.normalize(artist_name, album_name, track_name)
    [
      artist_name,
      album_name,
      track_name
    ].map { |s|
      s.downcase.strip.gsub(/\s+/, " ")
    }.join("||")
  end
end
