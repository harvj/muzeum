module CanonicalCatalog
  class ReleaseComparison
    attr_reader :groups, :shared

    def initialize(proposals)
      @groups = proposals.sort_by do |proposal|
        base = proposal.construction.base
        data = base.data
        [ slots(proposal).size, data.fetch("date"),
          proposal.existing && ReviewedConstruction.current_edition(proposal.existing) == data["id"] ? 0 : 1,
          data["country"].present? ? 0 : 1, data.fetch("id") ]
      end.group_by { |proposal| ConfigurationEvidence.key(proposal.construction.base) }.values
      @shared = groups.empty? ? [] : slots(groups.first.first).each_with_index.take_while do |_, index|
        groups.map { |group| slots(group.first)[index] }.combination(2).all? do |left, right|
          left && right && left.values_at(:medium, :position) == right.values_at(:medium, :position) && TrackComparison.compare(left, right) == :equivalent
        end
      end.map(&:first)
    end

    def representatives
      groups.map(&:first)
    end

    def representative_for(edition_id)
      group = groups.find do |members|
        sources(members.first).any? { |source| source["id"] == edition_id }
      end
      group&.first
    end

    def sources(proposal)
      proposal.construction.appearances.select { |edition| edition["supports_base_configuration"] }
    end

    def comparisons
      anchor = groups.first
      groups.drop(1).map { |group| [ anchor, group, align(slots(anchor.first).drop(shared.size), slots(group.first).drop(shared.size)) ] }
    end

    private

    def slots(proposal)
      proposal.construction.base.slots
    end

    def align(left, right)
      matches = left.map { |first| right.map { |second| TrackComparison.compare(first, second) == :equivalent } }
      scores = Array.new(left.size + 1) { Array.new(right.size + 1, 0) }
      (left.size - 1).downto(0) do |i|
        (right.size - 1).downto(0) do |j|
          scores[i][j] = matches[i][j] ? 1 + scores[i + 1][j + 1] : [ scores[i + 1][j], scores[i][j + 1] ].max
        end
      end

      pairs = []
      i = j = 0
      while i < left.size && j < right.size
        if matches[i][j]
          pairs << [ i, j ]
          i += 1
          j += 1
        elsif scores[i + 1][j] >= scores[i][j + 1]
          i += 1
        else
          j += 1
        end
      end

      start_left = start_right = 0
      (pairs + [ [ left.size, right.size ] ]).flat_map do |next_left, next_right|
        left_gap, right_gap = left[start_left...next_left], right[start_right...next_right]
        changes = Array.new([ left_gap.size, right_gap.size ].max) do |offset|
          first, second = left_gap[offset], right_gap[offset]
          moved = (first && right.any? { |track| TrackComparison.compare(first, track) == :equivalent }) ||
            (second && left.any? { |track| TrackComparison.compare(second, track) == :equivalent })
          label = if first && second && TrackComparison.compare(first, second) == :uncertain
            "Identity uncertain"
          elsif moved
            "Reordered"
          elsif first && second
            "Substituted"
          else
            first ? "Removed" : "Inserted"
          end
          [ first, second, label ]
        end
        start_left, start_right = next_left + 1, next_right + 1
        changes << [ left[next_left], right[next_right], "Shared recording" ] if next_left < left.size
        changes
      end
    end
  end
end
