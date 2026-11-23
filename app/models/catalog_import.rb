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
    return unless self.class.worker_enabled? && active?

    job = CanonicalCatalogJob.set(wait_until: due_at).perform_later(id)
    if due_at.future? && job && job.provider_job_id &&
        kind.in?([ "assessment", RecordingResolution::Investigation::KIND ])
      scheduled_id = self.class.connection.quote(job.job_id)
      self.class.where(id:, state: "pending", due_at:).update_all(
        "context = jsonb_set(context, '{scheduled_active_job_id}', to_jsonb(#{scheduled_id}::text))")
    end
    job
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    # A due request can be dispatched again from the page or the bounded recovery task.
    false
  end

  def automatic_retry_scheduled?
    return false unless state == "pending" && due_at.future? && context["scheduled_active_job_id"].present?
    return false unless CanonicalCatalogJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

    SolidQueue::ScheduledExecution.joins(:job)
      .exists?(solid_queue_jobs: { active_job_id: context["scheduled_active_job_id"] })
  rescue ActiveRecord::ActiveRecordError
    false
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
