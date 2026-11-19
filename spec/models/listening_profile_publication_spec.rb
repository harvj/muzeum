require "rails_helper"

RSpec.describe ListeningProfile do
  let(:owner) { User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "publication-owner", lastfm_username: "test-profile") }
  let(:account) { owner.source_account }
  let(:grant) { owner.user_lastfm_accounts.find_by!(lastfm_account: account) }
  let(:profile) { described_class.establish!(account:, owner:, reference: "ownership-1") }

  it "records consent independently and handles repeated commands without replacing evidence" do
    expect { profile.activate_publication!(provider_reference: "approval-1") }.to raise_error(ArgumentError, /consent/)
    2.times { profile.record_consent!(consenting_owner: owner, reference: "consent-1") }
    expect(described_class.published).to be_empty
    expect(profile.reload).to have_attributes(owner_consented_at: be_present, published_lookup_key: nil, provider_approval_reference: nil)
    expect { profile.record_consent!(consenting_owner: owner, reference: "different") }.to raise_error(ArgumentError)
    expect { profile.activate_publication!(provider_reference: "") }.to raise_error(ArgumentError)
    2.times { profile.activate_publication!(provider_reference: "approval-1") }
    expect { profile.activate_publication!(provider_reference: "different") }.to raise_error(ArgumentError)
    expect(described_class.published).to contain_exactly(profile)
    expect do
      described_class.transaction(requires_new: true) { profile.publication_events.delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /Source evidence is immutable/)
    expect(profile.publication_events.order(:id).pluck(:action, :evidence_reference))
      .to eq([ %w[consented consent-1], %w[activated approval-1] ])
  end

  it "withdraws access and current consent while preserving ownership and evidence" do
    profile.record_consent!(consenting_owner: owner, reference: "consent-1")
    profile.activate_publication!(provider_reference: "approval-1")
    2.times { profile.withdraw_publication!(reference: "withdrawal-1") }

    expect(described_class.published).to be_empty
    expect(profile.reload).to have_attributes(ownership_reference: "ownership-1", owner_consented_at: nil,
      published_lookup_key: nil, provider_approval_reference: nil)
    expect(profile.publication_events.order(:id).pluck(:action, :evidence_reference))
      .to eq([ %w[consented consent-1], %w[activated approval-1], %w[withdrawn withdrawal-1] ])
    expect { profile.activate_publication!(provider_reference: "approval-1") }.to raise_error(ArgumentError, /consent/)
    profile.record_consent!(consenting_owner: owner, reference: "consent-2")
    profile.activate_publication!(provider_reference: "approval-2")
    expect(described_class.published).to contain_exactly(profile)
  end

  it "invalidates visibility on grant revocation even outside Rails callbacks" do
    profile.record_consent!(consenting_owner: owner, reference: "consent-1")
    profile.activate_publication!(provider_reference: "approval-1")
    grant.update_columns(revoked_at: Time.current)
    expect(profile.reload.published_lookup_key).to be_nil
    expect(described_class.published).to be_empty
    expect { profile.activate_publication!(provider_reference: "approval-2") }.to raise_error(ArgumentError, /active archive grant/)
    expect(profile.publication_events.where(action: "grant_revoked").count).to eq(1)

    grant.update!(revoked_at: nil)
    expect(described_class.published).to be_empty
    profile.activate_publication!(provider_reference: "approval-2")
    expect(described_class.published).to contain_exactly(profile)

    grant.destroy!
    owner.user_lastfm_accounts.create!(lastfm_account: account)
    expect(described_class.published).to be_empty
    expect(profile.publication_events.where(action: "grant_revoked").count).to eq(2)
  end

  it "can withdraw consent before publication and rejects a disabled owner" do
    profile.record_consent!(consenting_owner: owner, reference: "consent-1")
    profile.withdraw_publication!(reference: "withdrawal-1")
    expect(profile.publication_events.order(:id).pluck(:action)).to eq(%w[consented withdrawn])
    owner.update!(disabled_at: Time.current)
    expect { profile.record_consent!(consenting_owner: owner, reference: "consent-2") }.to raise_error(ArgumentError)
    expect { profile.activate_publication!(provider_reference: "approval-2") }.to raise_error(ArgumentError)
    expect(described_class.published).to be_empty
  end
end
