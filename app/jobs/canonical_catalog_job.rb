class CanonicalCatalogJob < ApplicationJob
  queue_as :canonical_catalog
  self.enqueue_after_transaction_commit = true

  def perform(import_id)
    return unless CatalogImport.worker_enabled?

    request = CatalogImport.find(import_id)
    processed = CanonicalCatalog::Processor.new(request).call
    return unless processed

    request.dispatch if request.reload.state == "pending"
    if request.kind == "recording" && (recording = Recording.find_by(id: request.entity_id))
      Turbo::StreamsChannel.broadcast_update_to(RecordingResolution::CatalogContext.stream(recording),
        target: RecordingResolution::CatalogContext.target(recording),
        partial: "resolution_workspace/catalog_context", locals: { rows: RecordingResolution::CatalogContext.rows(recording) })
    end
  end
end
