class ReleaseConfigurationDecision < ApplicationRecord
  belongs_to :user
  belongs_to :release
  belongs_to :release_configuration, optional: true

  def readonly?
    persisted?
  end

  def self.latest_for(user, releases)
    where(user:, release_id: releases).select("DISTINCT ON (release_id) *")
      .order(:release_id, id: :desc)
  end

  def self.select!(user, release, configuration)
    user.with_lock do
      previous = latest_for(user, [ release.id ]).first
      unless previous&.release_configuration_id == configuration&.id
        create!(user:, release:, release_configuration: configuration)
      end
    end
  end
end
