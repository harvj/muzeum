module MuzeumShellPreflight
  def self.verify!(revision, configuration: ENV)
    selected = configuration.fetch("MUZEUM_SHELL_SELECTED_VERSION")
    adopted = configuration.fetch("MUZEUM_SHELL_ADOPTED_VERSION")
    review = configuration.fetch("APPLICATION_SHELL_REVIEW")
    executable = configuration.fetch("APPLICATION_SHELL_PREFLIGHT", "application-shell-preflight")
    arguments = [ "--app", "muzeum", "--revision", revision, "--version", selected,
      "--adopted-version", adopted, "--review", review ]
    if (checkpoint = configuration["APPLICATION_SHELL_STATE"])
      arguments.concat([ "--state", checkpoint ])
    end
    raise "Application Shell review failed for #{revision}" unless system(executable, *arguments)
  end
end
