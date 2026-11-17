class SourceFetch < ApplicationRecord
  belongs_to :import_run
  belongs_to :lastfm_account
end
