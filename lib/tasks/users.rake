namespace :users do
  desc "Explicitly link a retained legacy user to an operator-verified Auth subject; never by email"
  task :link, [ :user_id, :subject ] => :environment do |_, args|
    abort "Explicit user ID and verified stable Auth subject required" if args[:user_id].blank? || args[:subject].blank?
    user = User.find(args[:user_id])
    abort "Identity is already linked; reconcile explicitly" if user.oidc_subject.present?
    user.update!(oidc_issuer: OidcClient::ISSUER, oidc_subject: args[:subject])
    puts "Linked retained Muzeum profile #{user.id}. No Auth account or credentials created."
  end
end
