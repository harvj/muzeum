class MusicalIdentityDecision < ApplicationRecord
  belongs_to :entity, polymorphic: true
  belongs_to :user

  validates :entity_type, inclusion: { in: %w[Artist Release Recording] }
  validates :rationale, length: { maximum: 1000 }, presence: { if: -> { colors.size == 3 } }
  validate :valid_palette

  def self.latest_for(entries)
    entries.compact.group_by { |entry| entry.class.name }.each_with_object({}) do |(type, items), decisions|
      where(entity_type: type, entity_id: items.map(&:id)).select("DISTINCT ON (entity_id) musical_identity_decisions.*")
        .order(:entity_id, id: :desc).each { |decision| decisions[[ type, decision.entity_id ]] = decision }
    end
  end

  def self.presentation_for(entries)
    entries = entries.compact
    credits = {}
    { "Recording" => [ RecordingArtist, :recording_id ], "Release" => [ ReleaseArtist, :release_id ] }.each do |type, (join, key)|
      ids = entries.select { |entry| entry.class.name == type }.map(&:id)
      next if ids.empty?

      join.where(key => ids).pluck(key, :artist_id).each do |entity_id, artist_id|
        (credits[[ type, entity_id ]] ||= []) << artist_id
      end
    end

    artists = Artist.where(id: credits.values.flatten.uniq).index_by(&:id)
    decisions = latest_for(entries + artists.values)
    inherited = credits.filter_map do |key, ids|
      next if decisions[key]&.colors.present?

      sources = ids.uniq.filter_map do |id|
        artists.fetch(id) if decisions[[ "Artist", id ]]&.colors.present?
      end
      palettes = sources.map { |artist| decisions.fetch([ "Artist", artist.id ]).colors }.uniq
      [ key, { colors: palettes.first, artists: sources.sort_by { |artist| [ artist.name, artist.id ] } } ] if palettes.one?
    end.to_h

    [ decisions, inherited ]
  end

  private

  def valid_palette
    unless colors.size <= 3 && colors.uniq == colors && (colors - MusicalIdentity::Palette::COLORS.keys).empty?
      errors.add(:colors, "must be distinct choices from the palette, with at most three colors")
    end
  end
end
