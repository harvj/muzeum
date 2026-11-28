# Credit tables store zero-based positions from earlier imports. Expose one-based
# positions without rewriting historical rows or changing their SQL sort order.
class ArtistCreditPosition < ActiveRecord::Type::Integer
  def deserialize(value)
    super&.succ
  end

  def serialize(value)
    position = cast(value)
    super(position - 1) if position
  end
end
