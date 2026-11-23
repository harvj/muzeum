class ReleaseRanking
  def initialize(listener, releases)
    @releases = releases
    @decisions = ReleaseRankingDecision.latest_for(listener, releases.map(&:id))
    @original_ids = original_ids
  end

  def include?(release)
    decision = @decisions[release.id]
    decision ? decision.included? : @original_ids.include?(release.id)
  end

  private

  def original_ids
    verified = @releases.select(&:catalog_verified_at)
    revisions = CatalogRevision.where(entity_type: "Release", entity_id: verified.map(&:id))
      .where("evidence ? 'edition_mbid'").select("DISTINCT ON (entity_id) entity_id, evidence")
      .order(:entity_id, id: :desc).index_by(&:entity_id)
    supported_editions = CatalogRevision.where(entity_type: "Release", entity_id: verified.map(&:id))
      .where("evidence->'original_context' = 'true'::jsonb")
      .pluck(:entity_id, Arel.sql("evidence->>'edition_mbid'")).to_set
    first_publications = CatalogRevision.where(entity_type: "Recording",
      entity_id: CatalogTrackSlot.where(release_id: verified.map(&:id)).select(:recording_id))
      .where("evidence ? 'verified_publication'").select("DISTINCT ON (entity_id) entity_id, evidence")
      .order(:entity_id, id: :desc).to_h { |revision| [ revision.entity_id, revision.evidence.dig("verified_publication", "id") ] }
    memberships = CatalogTrackSlot.where(release_id: verified.map(&:id)).distinct.pluck(:release_id, :recording_id).group_by(&:first)
    verified.filter_map do |release|
      evidence = revisions[release.id]&.evidence || {}
      edition_id = evidence["edition_mbid"] || release.ingested_from_release_mbid
      next if edition_id.blank?

      first = Array(memberships[release.id]).any? { |_, id| first_publications[id] == edition_id }
      # Older verified constructions retain the checked base appearance but predate the explicit flag.
      legacy_original = release.primary_type.in?(%w[album single ep]) &&
        Array(evidence["checked_recording_appearances"]).first&.fetch("id", nil) == edition_id
      release.id if supported_editions.include?([ release.id, edition_id ]) || first ||
        (!evidence.key?("original_context") && legacy_original)
    end.to_set
  end
end
