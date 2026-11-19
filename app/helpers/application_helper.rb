module ApplicationHelper
  def published_release_tag
    path = Rails.configuration.x.published_release_path
    MuzeumPublishedRelease.from_file(path, revision: Rails.configuration.x.running_revision) if path
  end

  # The current Auth contract has no consumer administrator-role evidence.
  # Never infer this from email, subject, an application membership, or parameters.
  def auth_administration_available?
    false
  end
end
