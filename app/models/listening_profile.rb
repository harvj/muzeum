class ListeningProfile < ApplicationRecord
  belongs_to :lastfm_account
  belongs_to :owner, class_name: "User"

  has_many :publication_events, class_name: "ListeningProfilePublicationEvent"

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

  # These operations are exposed only through the protected operator runtime.
  def record_consent!(consenting_owner:, reference:)
    require_reference!(reference)

    lastfm_account.with_lock do
      with_lock do
        validate_current_owner!(consenting_owner)
        if owner_consented_at
          event = publication_events.find_by(action: "consented", created_at: owner_consented_at)
          next if event&.evidence_reference == reference
          raise ArgumentError, "Withdraw current consent before recording different evidence" if event
        end

        event = publication_events.create!(action: "consented", evidence_reference: reference)
        update!(owner_consented_at: event.created_at)
      end
    end
  end

  def activate_publication!(provider_reference:)
    require_reference!(provider_reference)

    lastfm_account.with_lock do
      with_lock do
        validate_current_owner!(owner)
        unless owner_consented_at && publication_events.exists?(action: "consented", created_at: owner_consented_at)
          raise ArgumentError, "Recorded owner consent is required"
        end

        if published_lookup_key
          next if published_lookup_key == lastfm_account.lookup_key && provider_approval_reference == provider_reference
          raise ArgumentError, "Withdraw current publication before changing its approval"
        end

        update!(published_lookup_key: lastfm_account.lookup_key, provider_approval_reference: provider_reference)
        publication_events.create!(action: "activated", evidence_reference: provider_reference)
      end
    end
  end

  def withdraw_publication!(reference:)
    require_reference!(reference)

    with_lock do
      next unless published_lookup_key || owner_consented_at || provider_approval_reference

      update!(published_lookup_key: nil, owner_consented_at: nil, provider_approval_reference: nil)
      publication_events.create!(action: "withdrawn", evidence_reference: reference)
    end
  end

  private

  def require_reference!(reference)
    raise ArgumentError, "A protected evidence reference is required" if reference.blank?
  end

  def validate_current_owner!(consenting_owner)
    unless consenting_owner.id == owner_id && owner.reload.login_enabled? &&
        lastfm_account.user_lastfm_accounts.active.exists?(user_id: owner_id)
      raise ArgumentError, "The Auth-linked owner needs an active archive grant"
    end
  end
end
