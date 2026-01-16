class User < ApplicationRecord
  has_many :daily_listens, dependent: :destroy
  has_many :import_runs, dependent: :destroy
  has_many :scrobbles, dependent: :destroy

  validates :lastfm_username, presence: true, uniqueness: true
end
