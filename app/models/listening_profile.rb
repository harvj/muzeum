class ListeningProfile < ApplicationRecord
  belongs_to :lastfm_account
  belongs_to :owner, class_name: "User"

  attr_readonly :lastfm_account_id, :owner_id, :ownership_basis, :ownership_reference

  scope :published, -> {
    joins(:lastfm_account, :owner)
      .where.not(owner_consented_at: nil)
      .where.not(provider_approval_reference: nil)
      .where("listening_profiles.published_lookup_key = lastfm_accounts.lookup_key")
      .where(users: { disabled_at: nil, oidc_issuer: OidcClient::ISSUER })
      .where.not(users: { oidc_subject: [ nil, "" ] })
      .where(<<~SQL.squish)
        EXISTS (SELECT 1 FROM user_lastfm_accounts
          WHERE user_lastfm_accounts.lastfm_account_id = listening_profiles.lastfm_account_id
            AND user_lastfm_accounts.user_id = listening_profiles.owner_id
            AND user_lastfm_accounts.revoked_at IS NULL)
      SQL
  }

  def self.establish!(account:, owner:, reference:)
    raise ArgumentError, "An administrative evidence reference is required" if reference.blank?

    account.with_lock do
      unless account.archive_user_id == owner.id && owner.reload.login_enabled? &&
          account.user_lastfm_accounts.active.exists?(user_id: owner.id)
        raise ArgumentError, "An active existing archive identity is required"
      end

      find_or_create_by!(lastfm_account: account) do |profile|
        profile.owner = owner
        profile.ownership_basis = "administrative"
        profile.ownership_reference = reference
      end.tap do |profile|
        raise ArgumentError, "This archive already has a different owner" unless profile.owner_id == owner.id
      end
    end
  end

  def to_param
    lastfm_account.lookup_key
  end

  # Operator records approval obtained from this specific owner. There is no public write route.
  def record_publication!(consenting_owner:, provider_reference:)
    raise ArgumentError, "Owner consent and a provider approval reference are required" unless
      consenting_owner.id == owner_id && provider_reference.present?

    lastfm_account.with_lock do
      unless owner.reload.login_enabled? && lastfm_account.user_lastfm_accounts.active.exists?(user_id: owner_id)
        raise ArgumentError, "The owner needs an active archive grant"
      end

      update!(published_lookup_key: lastfm_account.lookup_key,
        owner_consented_at: Time.current, provider_approval_reference: provider_reference)
    end
  end
end
