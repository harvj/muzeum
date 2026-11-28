require "json"
require "shellwords"
require_relative "muzeum_published_release"
require_relative "muzeum_publication_receipt"

# Shared steps for Muzeum's existing Capistrano staging and publication tasks.
module MuzeumReleaseIdentityTasks
  def muzeum_package_identity(artifact, revision, version, ruby:)
    workflow = File.join(artifact.to_s, "script/muzeum_release_identity.rb")
    execute :mkdir, "-p", shared_path.join("release-candidates"), shared_path.join("release-publications")
    candidate = JSON.parse(capture(ruby, workflow, "package", version, revision))
    puts "Packaged v#{version}-rc.#{candidate.fetch('candidate_number')} at #{candidate.fetch('artifact_sha256')}"
    candidate
  end

  def muzeum_verify_artifact(artifact, revision, ruby:)
    workflow = File.join(artifact.to_s, "script/muzeum_release_identity.rb")
    JSON.parse(capture(ruby, workflow, "verify", revision))
  end

  def muzeum_sync_release(tag, deployment:, status:, ruby:, command:)
    artifact = capture(:readlink, "-f", current_path)
    unless artifact.match?(%r{\A#{Regexp.escape(releases_path.to_s)}/[0-9]{14}\z})
      raise "Running release path is not a retained Capistrano artifact"
    end
    revision = capture(:cat, "#{artifact}/REVISION")
    if test(:test, "-f", "#{artifact}/ARTIFACT_IDENTITY.json")
      candidate = muzeum_verify_artifact(artifact, revision, ruby:)
      raise "Tag differs from the running candidate" unless tag == "v#{candidate.fetch('target_version')}"

      receipt = MuzeumPublicationReceipt.verify!(candidate, deployment_id: deployment, status_id: status, command:,
        asset_command: ->(*arguments) { command.call(*arguments, raw: true) })
      script = "printf '%s' #{Shellwords.escape(receipt.to_json)} | #{Shellwords.escape(ruby)} #{Shellwords.escape("#{artifact}/script/muzeum_release_identity.rb")} receipt"
      execute :bash, "-c", Shellwords.escape(script)
    else
      MuzeumPublishedRelease.verify!(revision, tag:, command:)
      execute ruby, "#{artifact}/lib/muzeum_published_release.rb", revision, tag
    end
    puts "Synchronized Muzeum #{tag} for live revision #{revision}"
  end
end
