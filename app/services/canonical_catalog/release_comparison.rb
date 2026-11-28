module CanonicalCatalog
  class ReleaseComparison
    attr_reader :groups, :shared

    def initialize(proposals)
      @groups = []
      proposals.sort_by do |proposal|
        data = proposal.construction.base.data
        [ slots(proposal).size, data.fetch("date"), data.fetch("id") ]
      end.each do |proposal|
        group = groups.find { |items| items.all? { |item| TrackComparison.equivalent_sequence?(slots(item), slots(proposal)) } }
        group ? group << proposal : groups << [ proposal ]
      end
      @shared = slots(groups.first.first).each_with_index.take_while do |_, index|
        groups.map { |group| slots(group.first)[index] }.combination(2).all? do |left, right|
          left && right && TrackComparison.compare(left, right) == :equivalent
        end
      end.map(&:first)
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
