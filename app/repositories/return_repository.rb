# typed: strict

class ReturnRepository < BaseRepository
  include ReturnRepositoryInterface
  extend T::Sig

  sig { void }
  def initialize
    super(Return)
  end

  sig { override.params(merchant_id: Integer, id: Integer).returns(T.nilable(Return)) }
  def find_by_id(merchant_id:, id:)
    T.cast(model.find_by(merchant_id: merchant_id, id: id), T.nilable(Return))
  end

  sig { override.params(merchant_id: Integer).returns(T::Array[Return]) }
  def find_by_merchant(merchant_id:)
    T.cast(model.where(merchant_id: merchant_id).order(created_at: :desc).to_a, T::Array[Return])
  end


  sig { override.params(merchant_id: Integer, order_id: Integer).returns(T.nilable(Return)) }
  def find_by_order_id(merchant_id:, order_id:)
    T.cast(model.find_by(merchant_id: merchant_id, order_id: order_id), T.nilable(Return))
  end

  sig { override.params(merchant_id: Integer, attributes: T::Hash[Symbol, T.anything]).returns(Return) }
  def create(merchant_id:, attributes:)
    T.cast(model.create!(attributes.merge(merchant_id: merchant_id)), Return)
  end

  sig do
    override.params(
      merchant_id: Integer,
      id: Integer,
      status: String,
      resolved_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone))
    ).returns(T.nilable(Return))
  end
  def update_status(merchant_id:, id:, status:, resolved_at: nil)
    record = find_by_id(merchant_id: merchant_id, id: id)
    return nil unless record

    updates = T.let({ status: status }, T::Hash[Symbol, T.anything])
    updates[:resolved_at] = resolved_at if resolved_at
    record.update!(updates)
    record
  end
end
