class SourceDelivery < ApplicationRecord
  belongs_to :source_fetch
  belongs_to :lastfm_account
  belongs_to :scrobble, optional: true
end
