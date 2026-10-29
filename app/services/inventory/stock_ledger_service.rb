# typed: strict

module Inventory
  class StockLedgerService
    extend T::Sig

    sig { returns(StockLedgerRepositoryInterface) }
    attr_reader :repository

    sig { params(repository: StockLedgerRepositoryInterface).void }
    def initialize(repository: T.let(Container[:stock_ledger_repository], StockLedgerRepositoryInterface))
      @repository = repository
    end

    sig { params(after: T.nilable(String), limit: Integer).returns(Page[BinSummary]) }
    def bins(after:, limit:)
      Page[BinSummary].new(repository.bins(after: after, count: limit + 1), limit)
    end

    sig { params(filter: StockFilter, after: T.nilable(Integer), limit: Integer).returns(Page[BinInventory]) }
    def stock(filter:, after:, limit:)
      Page[BinInventory].new(repository.stock(filter: filter, after: after, count: limit + 1), limit)
    end

    sig { params(filter: StockFilter, before: T.nilable(Integer), limit: Integer).returns(Page[StockReceipt]) }
    def receipts(filter:, before:, limit:)
      Page[StockReceipt].new(repository.receipts(filter: filter, before: before, count: limit + 1), limit)
    end

    sig { params(filter: StockFilter, before: T.nilable(Integer), limit: Integer).returns(Page[StockAdjustment]) }
    def adjustments(filter:, before:, limit:)
      Page[StockAdjustment].new(repository.adjustments(filter: filter, before: before, count: limit + 1), limit)
    end
  end
end
