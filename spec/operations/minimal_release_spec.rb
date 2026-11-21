require "spec_helper"
require "open3"
require "fileutils"
require "tmpdir"

RSpec.describe "Minimal Capistrano release" do
  let(:config) { File.read("ops/capistrano/config/deploy.rb") }
  let(:git_check) { config[/script = <<~SH\n(.*?)^  SH$/m, 1] }

  def capture!(*command, **options)
    output, error, result = Open3.capture3(*command, **options)
    raise "#{error}#{output}" unless result.success?

    output
  end

  it "checks the exact v0.3.6 and v0.4.0 trees and refuses changed executable inputs" do
    revisions = %w[c37a00dcf058e87fdc59644e9e444c001e29622f 96597aa6f94e64b6bb9cfdb7399de1ed98124a11]
    repository = capture!("git", "rev-parse", "--absolute-git-dir").strip
    Dir.mktmpdir("muzeum-minimal") do |temporary|
      revisions.each do |revision|
        release = File.join(temporary, revision)
        Dir.mkdir(release)
        archive = capture!("git", "--no-replace-objects", "archive", revision, binmode: true)
        capture!("tar", "-xf", "-", "-C", release, stdin_data: archive, binmode: true)
        File.write(File.join(release, "REVISION"), "#{revision}\n")
        shared = File.join(temporary, "shared")
        %w[.env storage log tmp/pids tmp/sockets public/assets].each do |link|
          path = File.join(release, link)
          FileUtils.rm_rf(path)
          File.symlink(File.join(shared, link), path)
        end
        check = [ "bash", "-c", git_check, "verify-tree", repository, release, revision, shared ]
        expect(capture!(*check)).to be_empty

        File.open(File.join(release, "config/boot.rb"), "a") { |file| file.puts("# substituted boot input") }
        stdout, _stderr, result = Open3.capture3(*check)
        expect(result).not_to be_success
        expect(stdout).to include("config/boot.rb")
      end
    end
  end

  it "refuses the unguarded deployment and default previous-release rollback entry points" do
    %w[deploy deploy:rollback].each do |task|
      _output, errors, result = Open3.capture3("bundle", "exec", "cap", "production", task, chdir: "ops/capistrano")
      expect(result).not_to be_success
      expect(errors).to include("Use muzeum:stage")
    end
  end
end
