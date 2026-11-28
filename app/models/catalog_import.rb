class CatalogImport < ApplicationRecord
  RECORDING_METADATA = "recording_metadata".freeze
  INVESTIGATION_WORKER_FAILURE = "Investigation worker failed unexpectedly.".freeze
  ACTIVE = %w[pending refreshing].freeze
  scope :active, -> { where(state: ACTIVE) }
  scope :due, -> { where(state: "pending", due_at: ..Time.current).or(where(state: "refreshing", lease_until: ..Time.current)) }

  def self.request!(kind, entity_id, context = {})
    active.find_by(kind:, entity_id:) || transaction(requires_new: true) do
      create!(kind:, entity_id:, context:, due_at: Time.current)
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.worker_enabled?
    Rails.env.test? || ENV["MUZEUM_CATALOG_WORKER"] == "1"
  end

  def dispatch
    return unless self.class.worker_enabled? && active?

    CanonicalCatalogJob.set(wait_until: due_at).perform_later(id)
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    false
  end

  def investigation_queue_state
    RecordingResolution::QueueStatus.new(self).state
  end

  def expired_investigation?
    kind == RecordingResolution::Investigation::KIND && created_at <= 1.day.ago &&
      (state == "pending" || (state == "refreshing" && !lease_until.future?))
  end

  def active?
    state.in?(ACTIVE)
  end

  def self.latest_recording_work(entity_id)
    latest([ "recording", RECORDING_METADATA ], entity_id)
  end

  def self.latest(kind, entity_id)
    where(kind:, entity_id:).order(id: :desc).first
  end
end
