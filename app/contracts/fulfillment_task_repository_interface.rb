# typed: strict

module FulfillmentTaskRepositoryInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(merchant_id: Integer, id: Integer).returns(T.nilable(FulfillmentTask)) }
  def find_by_id(merchant_id:, id:); end

  sig { abstract.params(merchant_id: Integer, order_number: String).returns(T.nilable(FulfillmentTask)) }
  def find_by_order_number(merchant_id:, order_number:); end

  sig do
    abstract.params(
      merchant_id: Integer,
      attributes: T::Hash[Symbol, T.anything],
      lines: T::Array[T::Hash[Symbol, T.anything]]
    ).returns(FulfillmentTask)
  end
  def create(merchant_id:, attributes:, lines:); end

  sig { abstract.params(merchant_id: Integer).returns(T::Array[FulfillmentTask]) }
  def open_work(merchant_id:); end

  sig do
    abstract.params(
      merchant_id: Integer, task_id: Integer, status: String, from: T.nilable(String)
    ).returns(T.nilable(FulfillmentTask))
  end
  def update_status(merchant_id:, task_id:, status:, from: nil); end

  sig { abstract.params(task_id: Integer, line_id: Integer).returns(T::Boolean) }
  def mark_line_scanned(task_id:, line_id:); end

  sig { abstract.params(task_id: Integer).returns(Integer) }
  def lines_remaining(task_id:); end
end
