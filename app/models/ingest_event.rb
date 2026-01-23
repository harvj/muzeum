class IngestEvent < ApplicationRecord
  belongs_to :recording_surface
  belongs_to :subject, polymorphic: true
end
