module ApplicationHelper
  def lastfm_import_error(run)
    return run.last_error unless run.paused? && run.failure_kind == "Clients::NetworkError"

    outcome = SourceFetch.where(import_run: run).order(id: :desc).pick(:outcome)
    case outcome
    when "provider_error"
      "Last.fm service error. Your saved listening history is still available."
    when "transport_error"
      "Muzeum could not reach Last.fm. Your saved listening history is still available."
    else
      run.last_error
    end
  end

  def shell_navigation_item(label, path, descendants: true)
    current = request.path == path || (descendants && request.path.start_with?("#{path}/"))
    if current && descendants
      tag.span(label, class: "library-nav-item", aria: { current: "page" })
    else
      link_to(label, path, class: "library-nav-item", aria: { current: ("page" if current) })
    end
  end

  def published_release_tag
    config = Rails.configuration.x
    [ config.published_release_path, config.reviewed_release_path ].compact.lazy.filter_map do |path|
      MuzeumPublishedRelease.from_file(path, revision: config.running_revision)
    end.first
  end

  def running_release_label
    config = Rails.configuration.x
    config.release_identity&.label || published_release_tag || config.development_release_label ||
      ("Version unavailable#{(" (#{config.running_revision})") if config.running_revision}" if Rails.env.production?)
  end

  # The current Auth contract has no consumer administrator-role evidence.
  # Never infer this from email, subject, an application membership, or parameters.
  def auth_administration_available?
    false
  end
end
