class CanonicalCatalogJob < ApplicationJob
  queue_as :canonical_catalog
  self.enqueue_after_transaction_commit = true

  def perform(import_id)
    return unless CatalogImport.worker_enabled?

    request = CatalogImport.find(import_id)
    processed = CanonicalCatalog::Processor.new(request).call
    request.dispatch if processed && request.reload.state == "pending"
  end
end
