class IngestionIssue < ApplicationRecord
  belongs_to :lastfm_account
  belongs_to :import_run, optional: true
  belongs_to :source_fetch, optional: true
end
