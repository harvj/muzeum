namespace :listening_profiles do
  desc "Record reviewed administrative ownership of an existing archive without publishing it"
  task :establish, [ :archive_id, :owner_id, :reference ] => :environment do |_, args|
    account = LastfmAccount.find(args[:archive_id])
    owner = User.find(args[:owner_id])
    profile = ListeningProfile.establish!(account:, owner:, reference: args[:reference])
    puts "Administrative ownership recorded for profile #{profile.id}. Publication is separate."
  end

  desc "Record reviewed owner consent while leaving publication visibility as-is"
  task :record_consent, [ :archive_id, :owner_id ] => :environment do |_, args|
    profile = ListeningProfile.find_by!(lastfm_account_id: args[:archive_id])
    profile.record_consent!(consenting_owner: User.find(args[:owner_id]),
      reference: ENV.fetch("MUZEUM_PUBLICATION_EVIDENCE_REFERENCE"))
    puts "Consent recorded for profile #{profile.id}."
  end

  desc "Activate public visibility using verified written provider approval"
  task :activate, [ :archive_id ] => :environment do |_, args|
    profile = ListeningProfile.find_by!(lastfm_account_id: args[:archive_id])
    profile.activate_publication!(provider_reference: ENV.fetch("MUZEUM_PUBLICATION_EVIDENCE_REFERENCE"))
    puts "Public visibility activated for profile #{profile.id}."
  end

  desc "Withdraw visibility and current consent while retaining publication history"
  task :withdraw, [ :archive_id ] => :environment do |_, args|
    profile = ListeningProfile.find_by!(lastfm_account_id: args[:archive_id])
    profile.withdraw_publication!(reference: ENV.fetch("MUZEUM_PUBLICATION_EVIDENCE_REFERENCE"))
    puts "Publication withdrawn for profile #{profile.id}."
  end
end
