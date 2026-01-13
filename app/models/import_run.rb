class ImportRun < ApplicationRecord
  belongs_to :user

  STATUSES = %w[
    pending
    running
    completed
    failed
  ].freeze

  validates :status, inclusion: { in: STATUSES }
end
