namespace :canonical_catalog do
  desc "Dispatch up to 25 due canonical catalog requests"
  task dispatch: :environment do
    abort "Canonical catalog worker is disabled" unless CatalogImport.worker_enabled?

    CatalogImport.due.order(:id).limit(25).each(&:dispatch)
  end
end
