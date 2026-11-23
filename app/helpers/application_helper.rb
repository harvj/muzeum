module ApplicationHelper
  def shell_navigation_item(label, path, descendants: true)
    current = request.path == path || (descendants && request.path.start_with?("#{path}/"))
    if current
      tag.span(label, class: "library-nav-item", aria: { current: "page" })
    else
      link_to(label, path, class: "library-nav-item")
    end
  end

  def published_release_tag
    config = Rails.configuration.x
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
