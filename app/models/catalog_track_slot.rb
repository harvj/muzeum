class CatalogTrackSlot < ApplicationRecord
  belongs_to :release
  belongs_to :recording
end
