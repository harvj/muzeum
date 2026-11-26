# Disposable native Auth bootstrap. The HTTPS loopback proxy preserves the real issuer.
require "json"
require "securerandom"
require File.expand_path("lib/runtime", Dir.pwd)

database = "postgres://127.0.0.1:55435/auth_poc_test_muzeumbrowser"
abort "Disposable Auth database required" unless ENV["DATABASE_URL"] == database
Auth::Runtime.singleton_class.prepend(Module.new do
  define_method(:validate!) do |issuer|
    return if environment == "test" && issuer == "https://auth.harvj.com" && ENV["DATABASE_URL"] == database

    super(issuer)
  end
end)
require File.expand_path("spec/spec_helper", Dir.pwd)
require "rackup"

root = ENV.fetch("MUZEUM_BROWSER_WORK")
db = Auth::DB
admin = db[:accounts].insert(email: "pilot-admin@example.test", admin: true, status_id: 2, email_verified_at: Time.now)
subject = db[:accounts].insert(email: "pilot-listener@example.test", status_id: 2, email_verified_at: Time.now)
password = SecureRandom.hex(24)
seed = ROTP::Base32.random
db[:account_password_hashes].insert(id: subject, password_hash: BCrypt::Password.create(password, cost: 4))
db[:account_otp_keys].with_extend(Auth::OtpStorage).insert(id: subject, key: seed)
Auth::AccountUsernames.backfill(db, nil)
Auth::AccountUsernames.update(db, subject, "archive-pilot")
internal, secret = Auth::Clients.register(admin, name: "Muzeum", redirect_uri: "https://muzeum.fm/oidc/callback",
  method: "client_secret_basic")
client = db[:oauth_applications].where(id: internal)
client.update(scopes: "openid offline_access", enabled: true)
client_id = client.get(:client_id)
db[:memberships].insert(account_id: subject, oauth_application_id: internal, active: true)
Auth::ApplicationApprovals.define_singleton_method(:configuration) do
  { "applications" => [ { "client_id" => client_id, "assurance" => "mfa_required", "environment" => "production" } ],
    "application_shell_clients" => { "muzeum" => client_id } }
end
File.write(File.join(root, "otp"), seed, perm: 0o600)
File.write(File.join(root, "identity.json"),
  JSON.generate(login: "pilot-listener@example.test", password:, username: "archive-pilot", subject:, client_id:, secret:), perm: 0o600)
Rackup::Server.start(app: Auth::App.app, Host: "127.0.0.1", Port: 55492, AccessLog: [])
