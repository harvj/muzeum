class DailyListen < ApplicationRecord
  belongs_to :user
  belongs_to :recording

  validates :date, presence: true
  validates :listen_count, numericality: { greater_than_or_equal_to: 0 }
  validates :total_duration_ms, numericality: { greater_than_or_equal_to: 0 }
end
