require "capistrano/setup"
require "capistrano/deploy"
require "capistrano/scm/git"
install_plugin Capistrano::SCM::Git
require "capistrano/bundler"
require "capistrano/rails/assets"
# The custom migration hook requires separate migration approval and a backup ID.
Dir.glob("lib/capistrano/tasks/*.rake").each { |task| import task }
