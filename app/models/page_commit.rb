class PageCommit < ApplicationRecord
  belongs_to :source_fetch
  belongs_to :import_page
end
