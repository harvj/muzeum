namespace :listening_profiles do
  desc "Record reviewed administrative ownership of an existing archive without publishing it"
  task :establish, [ :archive_id, :owner_id, :reference ] => :environment do |_, args|
    account = LastfmAccount.find(args[:archive_id])
    owner = User.find(args[:owner_id])
    profile = ListeningProfile.establish!(account:, owner:, reference: args[:reference])
    puts "Administrative ownership recorded for profile #{profile.id}. Publication is separate."
  end
end
