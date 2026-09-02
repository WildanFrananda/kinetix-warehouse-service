# typed: strict

module ReturnRepositoryInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(merchant_id: Integer, id: Integer).returns(T.nilable(Return)) }
  def find_by_id(merchant_id:, id:); end

  sig { abstract.params(merchant_id: Integer).returns(T::Array[Return]) }
  def find_by_merchant(merchant_id:); end


  sig { abstract.params(merchant_id: Integer, order_id: Integer).returns(T.nilable(Return)) }
  def find_by_order_id(merchant_id:, order_id:); end

  sig { abstract.params(merchant_id: Integer, attributes: T::Hash[Symbol, T.anything]).returns(Return) }
  def create(merchant_id:, attributes:); end

  sig do
    abstract.params(
      merchant_id: Integer,
      id: Integer,
      status: String,
      resolved_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone))
    ).returns(T.nilable(Return))
  end
  def update_status(merchant_id:, id:, status:, resolved_at: nil); end
end
