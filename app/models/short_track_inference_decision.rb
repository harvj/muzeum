class ShortTrackInferenceDecision < ApplicationRecord
  belongs_to :user
  belongs_to :release
  belongs_to :recording
  belongs_to :before_play, class_name: "Scrobble"
  belongs_to :after_play, class_name: "Scrobble"
  belongs_to :predecessor, class_name: "ShortTrackInferenceDecision", optional: true

  def readonly?
    persisted?
  end
end
