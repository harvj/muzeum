module RecordingResolution
  class ProviderBudget < ApplicationRecord
    self.table_name = "resolution_provider_budgets"
    self.primary_key = "provider"
  end
end
