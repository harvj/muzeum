require "io/console"

namespace :users do
  desc "Provision/reset an explicitly selected local login; reads password without echo"
  task :provision, [ :user_id ] => :environment do |_, args|
    abort "Interactive terminal required" unless $stdin.tty?
    user = args[:user_id] ? User.find(args[:user_id]) : User.new
    print "Local email address: "
    email = $stdin.gets&.strip
    print "Password (12–72 bytes): "
    password = $stdin.noecho(&:gets)&.chomp
    puts
    print "Confirm password: "
    confirmation = $stdin.noecho(&:gets)&.chomp
    puts
    user.update!(email_address: email, password: password, password_confirmation: confirmation,
      activated_at: Time.current, disabled_at: nil)
    puts "Provisioned local User #{user.id}; no Last.fm account ownership was assigned."
  end
end
