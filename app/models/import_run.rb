class ImportRun < ApplicationRecord
  belongs_to :user
  belongs_to :lastfm_account, optional: true
  before_validation { self.lastfm_account ||= user&.source_account }

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
    superseded: 4,
    paused: 5
  }
end
