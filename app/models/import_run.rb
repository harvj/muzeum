class ImportRun < ApplicationRecord
  belongs_to :user

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3
  }
end
