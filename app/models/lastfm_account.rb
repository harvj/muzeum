class LastfmAccount < ApplicationRecord
  belongs_to :archive_user, class_name: "User"
  has_many :user_lastfm_accounts
  has_many :scrobbles
  has_many :import_runs
  scope :active, -> { where(state: "active") }

  def authorized_memberships
    user_lastfm_accounts.where(revoked_at: nil, import_allowed: true).joins(:user)
      .where(users: { disabled_at: nil, oidc_issuer: OidcClient::ISSUER }).where.not(users: { oidc_subject: nil })
  end

  def authorize!(run = nil)
    raise Lastfm::PermissionDenied unless state == "active"
    grant = authorized_memberships
    grant = grant.where(user_id: run.user_id) if run&.actor_kind == "user"
    raise Lastfm::PermissionDenied unless grant.exists?
  end

  def self.associate!(user, username)
    transaction do
      key = username.downcase
      name = LastfmAccountName.find_by(lookup_key: key)
      account = name&.lastfm_account || find_by(lookup_key: key)
      if account && account.lookup_key != key
        raise Lastfm::AccountConflict, "Reserved prior username requires operator reconciliation"
      end
      account ||= create!(username: username, lookup_key: key, identity_key: key, archive_user: user)
      account.with_lock do
        membership = UserLastfmAccount.find_by(user:, lastfm_account: account)
        if !membership && ListeningProfile.where(lastfm_account: account).where.not(owner: user).exists?
          raise Lastfm::AccountConflict, "An owned archive requires an existing grant"
        end

        LastfmAccountName.find_or_create_by!(lookup_key: key) do |record|
          record.lastfm_account = account
          record.reason = "public username association; ownership unverified"
        end
        membership ||= UserLastfmAccount.create!(user:, lastfm_account: account)
        raise Lastfm::AccountConflict, "Revoked association requires explicit reinstatement" if membership.revoked_at
      end
      account
    end
  end

  # Operator only; callers must validate the new public username independently.
  # Old names remain reserved. Never merge archives or rewrite fingerprints.
  def reconcile_name!(validated_username, reason:)
    raise ArgumentError if reason.blank? || !validated_username.match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
    with_lock do
      raise Lastfm::AccountConflict if import_runs.where(status: %i[pending running]).exists?
      key = validated_username.downcase
      prior = LastfmAccountName.find_by(lookup_key: key)
      raise Lastfm::AccountConflict if prior && prior.lastfm_account_id != id
      LastfmAccountName.create!(lastfm_account: self, lookup_key: key, reason: reason) unless prior
      IngestionIssue.create!(lastfm_account: self, kind: "name_reconciliation", details: { previous: username, reported: validated_username, reason: reason })
      update!(username: validated_username, lookup_key: key, state: "paused", sync_enabled: false)
    end
  end
end
