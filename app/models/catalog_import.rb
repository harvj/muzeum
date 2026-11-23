class CatalogImport < ApplicationRecord
  RECORDING_METADATA = "recording_metadata".freeze
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
    CanonicalCatalogJob.set(wait_until: due_at).perform_later(id) if self.class.worker_enabled? && active?
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    # A due request can be dispatched again from the page or the bounded recovery task.
    false
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
