class ReleaseRankingDecision < ApplicationRecord
  belongs_to :user
  belongs_to :release

  def self.latest_for(user, release_ids)
    where(user:, release_id: release_ids).select("DISTINCT ON (release_id) release_ranking_decisions.*")
      .order(:release_id, id: :desc).index_by(&:release_id)
  end
end
