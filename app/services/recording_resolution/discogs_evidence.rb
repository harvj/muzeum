module RecordingResolution
  class DiscogsEvidence
    # Resource ceilings per investigation. ProviderSession also enforces the pilot-wide budget.
    MAX_SEARCH_PAGES = 3
    MAX_RELEASE_DETAILS = 3

    def initialize(client, expanded: false)
      @client = client
      @expanded = expanded
    end

    def compare(surface, musicbrainz_edition, evidence)
      if surface.album.blank?
        evidence["status"] = "no_album_context"
        return
      end

      evidence.merge!("status" => "incomplete", "search_pages" => [], "matching_release_ids" => [],
        "releases" => [], "incomplete_reasons" => [])
      unless @client
        evidence["incomplete_reasons"] << "provider_unconfigured"
        return
      end
      references = @expanded ? cross_references(musicbrainz_edition) : []
      evidence["cross_reference_ids"] = references if @expanded
      evidence["matching_release_ids"].concat(references)
      search(surface, evidence)

      ids = evidence["matching_release_ids"]
      limits = evidence["incomplete_reasons"]
      limits << "release_detail_limit" if ids.size > MAX_RELEASE_DETAILS
      ids.first(MAX_RELEASE_DETAILS).each do |id|
        comparison = compare_release(id, surface, musicbrainz_edition)
        evidence["releases"] << comparison
        if comparison["status"] == "unverified" && !limits.include?("unverified_release_details")
          limits << "unverified_release_details"
        end
      end

      comparisons = evidence["releases"].pluck("status")
      evidence["status"] = comparison_status(comparisons, evidence["incomplete_reasons"])
    end

    private

    def search(surface, evidence)
      pages = evidence["search_pages"]
      ids = evidence["matching_release_ids"]
      MAX_SEARCH_PAGES.times do |index|
        page = index + 1
        result = @client.search_release(artist: surface.artist, title: surface.album, page:)
        unless result
          evidence["incomplete_reasons"] << "search_unavailable"
          return
        end

        pagination = result.fetch("pagination")
        rows = result.fetch("results")
        pages << pagination.merge("results_examined" => rows.size)
        unless consistent_page?(page, pagination, rows, pages.first)
          evidence["incomplete_reasons"] << "inconsistent_pagination"
          return
        end

        unless rows.all? { |item| item["title"].is_a?(String) && item["id"].is_a?(Integer) && item["id"].positive? }
          evidence["incomplete_reasons"] << "invalid_search_results"
          return
        end

        ids.replace(ids | rows.select { |item| text_matches?(item["title"], "#{surface.artist} - #{surface.album}") }.pluck("id"))
        return if page >= pagination.fetch("pages")
      end
      evidence["incomplete_reasons"] << "search_page_limit"
    end

    def consistent_page?(page, pagination, rows, first)
      reported_pages, items, per_page = pagination.values_at("pages", "items", "per_page")
      return false unless [ reported_pages, items, per_page ].all?(Integer)
      return false unless items >= 0 && per_page.between?(1, Clients::Discogs::SEARCH_PAGE_SIZE)

      expected_pages = items.fdiv(per_page).ceil
      remaining = items - (page - 1) * per_page
      pagination["page"] == page && (reported_pages == expected_pages || (items.zero? && reported_pages == 1)) &&
        pagination.slice("pages", "items", "per_page") == first.slice("pages", "items", "per_page") &&
        rows.size == remaining.clamp(0, per_page)
    end

    def compare_release(id, surface, musicbrainz_edition)
      edition = @client.release(id)
      comparison = { "release_id" => id, "status" => "unverified" }
      return comparison.merge("reason" => "release_unavailable") unless edition

      comparison["master_id"] = edition["master_id"]
      credit = edition.fetch("artists").map { |artist| "#{artist["anv"].presence || artist["name"]}#{artist["join"]}" }.join
      unless edition["id"] == id && text_matches?(edition["title"], surface.album) && text_matches?(credit, surface.artist)
        return comparison.merge("reason" => "release_identity_mismatch", "id_matches" => edition["id"] == id,
          "title_matches" => text_matches?(edition["title"], surface.album), "credit_matches" => text_matches?(credit, surface.artist))
      end

      slots = track_slots(edition.fetch("tracklist"))
      return comparison.merge("reason" => "empty_tracklist") if slots.empty?

      matches = slots.select { |track| track["title"] == surface.track }
      comparison.merge("status" => matches.any? ? "corroborates" : "track_absent",
        "slot_count" => matches.size, "matching_positions" => matches.pluck("position"),
        "country_agreement" => agreement(edition["country"], musicbrainz_edition&.fetch("country", nil)),
        "release_year_agreement" => agreement(edition["year"]&.to_s, musicbrainz_edition&.fetch("date", nil)&.slice(0, 4)))
    end

    def text_matches?(left, right)
      return left == right unless @expanded

      left.to_s.squish.casecmp?(right.to_s.squish)
    end

    def cross_references(edition)
      Array(edition&.fetch("relations", nil)).filter_map do |relation|
        url = relation.dig("url", "resource").to_s
        id = url[%r{\Ahttps?://(?:www\.)?discogs\.com/(?:[^/]+/)?release/(\d+)(?:[-/?#]|\z)}i, 1]
        id.to_i if id
      end.uniq.first(MAX_RELEASE_DETAILS)
    end

    def track_slots(entries)
      entries.flat_map do |entry|
        nested = track_slots(Array(entry["sub_tracks"]))
        entry["type_"] == "track" ? [ entry, *nested ] : nested
      end
    end

    def comparison_status(comparisons, incomplete_reasons)
      return "mixed" if comparisons.include?("corroborates") && comparisons.include?("track_absent")
      return "incomplete" if incomplete_reasons.any?
      return "no_matching_release" if comparisons.empty?
      return "corroborates" if comparisons.include?("corroborates")

      "contradicts"
    end

    def agreement(left, right)
      left == right if left.present? && right.present?
    end
  end
end
