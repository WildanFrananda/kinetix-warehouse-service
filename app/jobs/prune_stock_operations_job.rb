# typed: strict
# frozen_string_literal: true

class PruneStockOperationsJob < ApplicationJob
  extend T::Sig

  queue_as :default

  RETENTION = T.let(7.days, ActiveSupport::Duration)

  sig { void }
  def perform
    StockOperation.older_than(RETENTION.ago)
                  .where(conflict_count: 0)
                  .in_batches(of: 1_000)
                  .delete_all
  end
end
