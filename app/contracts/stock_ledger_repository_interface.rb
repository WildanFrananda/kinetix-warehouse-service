# typed: strict

module StockLedgerRepositoryInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(after: T.nilable(String), count: Integer).returns(T::Array[Inventory::BinSummary]) }
  def bins(after:, count:); end

  sig do
    abstract.params(filter: Inventory::StockFilter, after: T.nilable(Integer), count: Integer)
      .returns(T::Array[BinInventory])
  end
  def stock(filter:, after:, count:); end

  sig do
    abstract.params(filter: Inventory::StockFilter, before: T.nilable(Integer), count: Integer)
      .returns(T::Array[StockReceipt])
  end
  def receipts(filter:, before:, count:); end

  sig do
    abstract.params(filter: Inventory::StockFilter, before: T.nilable(Integer), count: Integer)
      .returns(T::Array[StockAdjustment])
  end
  def adjustments(filter:, before:, count:); end
end
