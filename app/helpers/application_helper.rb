module ApplicationHelper
  def published_release_tag
    config = Rails.configuration.x
    return config.artifact_identity.label if config.artifact_identity
    return if config.artifact_identity_present
    return config.development_version if config.development_version

    [ config.published_release_path, config.reviewed_release_path ].compact.lazy.filter_map do |path|
      MuzeumPublishedRelease.from_file(path, revision: config.running_revision)
    end.first
  end

  # The current Auth contract has no consumer administrator-role evidence.
  # Never infer this from email, subject, an application membership, or parameters.
  def auth_administration_available?
    false
  end
end
