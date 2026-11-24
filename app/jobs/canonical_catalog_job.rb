class CanonicalCatalogJob < ApplicationJob
  queue_as :canonical_catalog
  self.enqueue_after_transaction_commit = true

  def perform(import_id)
    return unless CatalogImport.worker_enabled?

    request = CatalogImport.find(import_id)
    investigation = request.kind.in?([ "assessment", RecordingResolution::Investigation::KIND ])
    investigation_lease = nil
    processed = CanonicalCatalog::Processor.new(request).call do
      if investigation
        investigation_lease = request.lease_token
        refresh_investigation(request)
      end
    end
    return unless processed

    request.dispatch if request.reload.state == "pending"
    refresh_investigation(request) if investigation
    if request.kind.in?([ "recording", CatalogImport::RECORDING_METADATA ]) && (recording = Recording.find_by(id: request.entity_id))
      Turbo::StreamsChannel.broadcast_update_to(RecordingResolution::CatalogContext.stream(recording),
        target: RecordingResolution::CatalogContext.target(recording),
        partial: "resolution_workspace/catalog_context", locals: { rows: RecordingResolution::CatalogContext.rows(recording) })
    end
  rescue StandardError
    fail_investigation(request, investigation_lease) if investigation_lease
    raise
  end

  private

  def fail_investigation(request, lease)
    updated = CatalogImport.where(id: request.id, state: "refreshing", lease_token: lease).update_all(
      state: "failed", failure: CatalogImport::INVESTIGATION_WORKER_FAILURE, lease_token: nil, lease_until: nil, updated_at: Time.current)
    refresh_investigation(request) if updated.positive?
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("Investigation failure state could not be saved for #{request.id}: #{error.class}")
  end

  def refresh_investigation(request)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
  rescue StandardError => error
    Rails.logger.warn("Investigation refresh failed for #{request.id}: #{error.class}")
  end
end
