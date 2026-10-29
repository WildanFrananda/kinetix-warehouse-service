# typed: strict

class StockLedgerRepository
  include StockLedgerRepositoryInterface
  extend T::Sig

  BIN_TOTALS = T.let(
    [
      "warehouse_bins.*",
      "COUNT(bin_inventories.id) FILTER (WHERE bin_inventories.quantity > 0) AS sku_count",
      "COALESCE(SUM(bin_inventories.quantity), 0) AS total_quantity",
      "COALESCE(SUM(bin_inventories.reserved_quantity), 0) AS total_reserved_quantity"
    ].freeze,
    T::Array[String]
  )

  sig { override.params(after: T.nilable(String), count: Integer).returns(T::Array[Inventory::BinSummary]) }
  def bins(after:, count:)
    scope = WarehouseBin.left_joins(:bin_inventories).group(:id).select(BIN_TOTALS).order(:bin_code).limit(count)
    scope = scope.where(WarehouseBin.arel_table[:bin_code].gt(after)) unless after.nil?

    scope.map { |bin| Inventory::BinSummary.of(bin) }
  end

  sig do
    override.params(filter: Inventory::StockFilter, after: T.nilable(Integer), count: Integer)
      .returns(T::Array[BinInventory])
  end
  def stock(filter:, after:, count:)
    scope = narrowed(BinInventory.joins(:warehouse_bin).preload(:warehouse_bin), filter).order(:id).limit(count)
    scope = scope.where(BinInventory.arel_table[:id].gt(after)) unless after.nil?

    scope.to_a
  end

  sig do
    override.params(filter: Inventory::StockFilter, before: T.nilable(Integer), count: Integer)
      .returns(T::Array[StockReceipt])
  end
  def receipts(filter:, before:, count:)
    scope = narrowed(StockReceipt.joins(:warehouse_bin).preload(:warehouse_bin), filter).order(id: :desc).limit(count)
    scope = scope.where(StockReceipt.arel_table[:id].lt(before)) unless before.nil?

    scope.to_a
  end

  sig do
    override.params(filter: Inventory::StockFilter, before: T.nilable(Integer), count: Integer)
      .returns(T::Array[StockAdjustment])
  end
  def adjustments(filter:, before:, count:)
    scope = narrowed(StockAdjustment.joins(:warehouse_bin).preload(:warehouse_bin), filter)
      .order(id: :desc)
      .limit(count)
    scope = scope.where(StockAdjustment.arel_table[:id].lt(before)) unless before.nil?

    scope.to_a
  end

  private

  sig { params(scope: T.untyped, filter: Inventory::StockFilter).returns(T.untyped) }
  def narrowed(scope, filter)
    scope = scope.where(sku: filter.sku) unless filter.sku.nil?
    scope = scope.where(merchant_principal_id: filter.merchant_principal_id) unless filter.merchant_principal_id.nil?
    scope = scope.where(warehouse_bins: { bin_code: filter.bin_code }) unless filter.bin_code.nil?

    scope
  end
end
