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
    return unless active?
    return :investigating if state == "refreshing" && lease_until&.future?

    adapter = CanonicalCatalogJob.queue_adapter
    return unless adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

    jobs = SolidQueue::Job.where(queue_name: "canonical_catalog", finished_at: nil, class_name: CanonicalCatalogJob.name)
      .where("arguments::jsonb -> 'arguments' -> 0 = CAST(? AS jsonb)", id.to_s)
    return :queued if jobs.joins(:ready_execution).exists? || jobs.joins(:blocked_execution).exists? ||
      (state == "pending" && jobs.joins(:claimed_execution).exists?)

    scheduled = jobs.joins(:scheduled_execution).minimum("solid_queue_scheduled_executions.scheduled_at")
    return unless scheduled

    due_at.future? && scheduled.future? ? :retrying : :queued
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("Investigation queue lookup failed for #{id}: #{error.class}")
    :unavailable
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
