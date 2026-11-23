class CanonicalCatalogJob < ApplicationJob
  queue_as :canonical_catalog
  self.enqueue_after_transaction_commit = true

  def perform(import_id)
    return unless CatalogImport.worker_enabled?

    request = CatalogImport.find(import_id)
    investigation = request.kind.in?([ "assessment", RecordingResolution::Investigation::KIND ])
    processed = CanonicalCatalog::Processor.new(request).call { refresh_investigation(request) if investigation }
    return unless processed

    request.dispatch if request.reload.state == "pending"
    refresh_investigation(request) if investigation
    if request.kind.in?([ "recording", CatalogImport::RECORDING_METADATA ]) && (recording = Recording.find_by(id: request.entity_id))
      Turbo::StreamsChannel.broadcast_update_to(RecordingResolution::CatalogContext.stream(recording),
        target: RecordingResolution::CatalogContext.target(recording),
        partial: "resolution_workspace/catalog_context", locals: { rows: RecordingResolution::CatalogContext.rows(recording) })
    end
  end
  private

  def refresh_investigation(request)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
  rescue StandardError => error
    Rails.logger.warn("Investigation refresh failed for #{request.id}: #{error.class}")
  end
end
