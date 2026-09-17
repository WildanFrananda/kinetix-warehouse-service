# typed: strict
# frozen_string_literal: true

module Inventory
  class AdjustStockService
    extend T::Sig

    class WrongOwner < StandardError; end
    class OwnerlessStock < StandardError; end
    class WouldCutReserved < StandardError; end

    BIN_NOT_FOUND = "BIN_NOT_FOUND"
    STOCK_NOT_FOUND = "STOCK_NOT_FOUND"
    INVALID_DELTA = "INVALID_DELTA"
    UNKNOWN_REASON = "UNKNOWN_REASON"
    WRONG_OWNER = "WRONG_OWNER"
    STOCK_HAS_NO_OWNER = "STOCK_HAS_NO_OWNER"
    WOULD_CUT_RESERVED = "WOULD_CUT_RESERVED"

    class Result < T::Struct
      const :adjustment, T.nilable(StockAdjustment)
      const :quantity_on_hand, Integer
      const :reserved_quantity, Integer
      const :replayed, T::Boolean
      const :error, T.nilable(String)
    end

    sig do
      params(
        bin_code: String,
        sku: String,
        quantity_delta: Integer,
        reason: String,
        idempotency_key: String,
        adjusted_by_principal_id: String,
        merchant_principal_id: String,
        note: T.nilable(String)
      ).void
    end
    def initialize(bin_code:, sku:, quantity_delta:, reason:, idempotency_key:,
                   adjusted_by_principal_id:, merchant_principal_id:, note: nil)
      @bin_code = bin_code
      @sku = sku
      @quantity_delta = quantity_delta
      @reason = reason
      @idempotency_key = idempotency_key
      @adjusted_by_principal_id = adjusted_by_principal_id
      @merchant_principal_id = merchant_principal_id
      @note = note
    end

    sig { returns(Result) }
    def call
      return failure(INVALID_DELTA) if @quantity_delta.zero?
      return failure(UNKNOWN_REASON) unless StockAdjustment::REASONS.include?(@reason)
      return failure(WRONG_OWNER) if @merchant_principal_id.to_s.empty?

      existing = StockAdjustment.find_by(idempotency_key: @idempotency_key)
      return replay(existing) if existing

      bin = WarehouseBin.find_by(bin_code: @bin_code)
      return failure(BIN_NOT_FOUND) if bin.nil?

      adjustment = T.let(nil, T.nilable(StockAdjustment))
      on_hand = T.let(0, Integer)
      reserved = T.let(0, Integer)

      ActiveRecord::Base.transaction do
        inventory = BinInventory.lock("FOR UPDATE").find_by(warehouse_bin_id: bin.id, sku: @sku)
        raise ActiveRecord::RecordNotFound if inventory.nil?

        owner = inventory.merchant_principal_id
        raise OwnerlessStock if owner.blank?
        raise WrongOwner if owner != @merchant_principal_id

        before = inventory.quantity.to_i
        reserved = inventory.reserved_quantity.to_i
        after = before + @quantity_delta

        # Below `reserved` is the line, not below zero: units already promised to orders are not the
        # warehouse's to write off.
        raise WouldCutReserved if after < reserved

        inventory.update!(quantity: after)
        on_hand = after

        adjustment = StockAdjustment.create!(
          warehouse_bin: bin,
          sku: @sku,
          merchant_principal_id: @merchant_principal_id,
          quantity_delta: @quantity_delta,
          reason: @reason,
          note: @note,
          idempotency_key: @idempotency_key,
          adjusted_by_principal_id: @adjusted_by_principal_id,
          quantity_before: before,
          quantity_after: after
        )
      end

      Result.new(adjustment: adjustment, quantity_on_hand: on_hand, reserved_quantity: reserved,
                 replayed: false, error: nil)
    rescue ActiveRecord::RecordNotFound
      failure(STOCK_NOT_FOUND)
    rescue OwnerlessStock
      failure(STOCK_HAS_NO_OWNER)
    rescue WrongOwner
      failure(WRONG_OWNER)
    rescue WouldCutReserved
      # The numbers go back with the refusal: "you may write off 3 of the 11" is actionable, a bare
      # 409 sends somebody to the database to find out why.
      failure(WOULD_CUT_RESERVED, on_hand: current_quantity, reserved: current_reserved)
    rescue ActiveRecord::RecordNotUnique
      replay(StockAdjustment.find_by(idempotency_key: @idempotency_key))
    end

    private

    sig { returns(T.nilable(BinInventory)) }
    def current_inventory
      bin = WarehouseBin.find_by(bin_code: @bin_code)
      return nil if bin.nil?

      BinInventory.find_by(warehouse_bin_id: bin.id, sku: @sku)
    end

    sig { returns(Integer) }
    def current_quantity
      current_inventory&.quantity.to_i
    end

    sig { returns(Integer) }
    def current_reserved
      current_inventory&.reserved_quantity.to_i
    end

    sig { params(adjustment: T.nilable(StockAdjustment)).returns(Result) }
    def replay(adjustment)
      return failure(STOCK_NOT_FOUND) if adjustment.nil?

      inventory = BinInventory.find_by(warehouse_bin_id: adjustment.warehouse_bin_id, sku: adjustment.sku)
      Result.new(
        adjustment: adjustment,
        quantity_on_hand: inventory&.quantity.to_i,
        reserved_quantity: inventory&.reserved_quantity.to_i,
        replayed: true,
        error: nil
      )
    end

    sig { params(code: String, on_hand: Integer, reserved: Integer).returns(Result) }
    def failure(code, on_hand: 0, reserved: 0)
      Result.new(adjustment: nil, quantity_on_hand: on_hand, reserved_quantity: reserved,
                 replayed: false, error: code)
    end
  end
end
