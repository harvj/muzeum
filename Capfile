require "capistrano/setup"
require "capistrano/deploy"
require "capistrano/scm/git"
install_plugin Capistrano::SCM::Git
require "capistrano/bundler"
require "capistrano/rails/assets"
# Muzeum hooks pin local main and coordinate reviewed backup/migration/recovery phases.
Dir.glob("lib/capistrano/tasks/*.rake").each { |task| import task }
