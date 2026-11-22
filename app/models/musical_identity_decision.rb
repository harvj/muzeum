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

  private

  def valid_palette
    unless colors.size <= 3 && colors.uniq == colors && (colors - MusicalIdentity::Palette::COLORS.keys).empty?
      errors.add(:colors, "must be distinct choices from the palette, with at most three colors")
    end
  end
end
