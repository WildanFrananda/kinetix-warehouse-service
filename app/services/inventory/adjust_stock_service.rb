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
    INVALID_MERCHANT_PRINCIPAL = "INVALID_MERCHANT_PRINCIPAL"
    IDEMPOTENCY_KEY_CONFLICT = "IDEMPOTENCY_KEY_CONFLICT"

    class Result < T::Struct
      const :adjustment, T.nilable(StockAdjustment)
      const :bin_code, T.nilable(String)
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

      owner = Kinetix::PrincipalId.canonical(@merchant_principal_id)
      return failure(INVALID_MERCHANT_PRINCIPAL) if owner.nil?

      existing = stored_adjustment(owner)
      return replay(existing) if existing

      bin = WarehouseBin.find_by(bin_code: @bin_code)
      return failure(BIN_NOT_FOUND) if bin.nil?

      adjust(bin, owner)
    end

    private

    sig { params(bin: WarehouseBin, owner: String).returns(Result) }
    def adjust(bin, owner)
      adjustment = T.let(nil, T.nilable(StockAdjustment))
      on_hand = T.let(0, Integer)
      reserved = T.let(0, Integer)

      ActiveRecord::Base.transaction do
        inventory = BinInventory.lock("FOR UPDATE").find_by(warehouse_bin_id: bin.id, sku: @sku)
        raise ActiveRecord::RecordNotFound if inventory.nil?

        recorded_owner = inventory.merchant_principal_id
        raise OwnerlessStock if recorded_owner.blank?
        raise WrongOwner if recorded_owner != owner

        before = inventory.quantity.to_i
        reserved = inventory.reserved_quantity.to_i
        after = before + @quantity_delta
        raise WouldCutReserved if after < reserved

        inventory.update!(quantity: after)
        on_hand = after

        adjustment = StockAdjustment.create!(
          warehouse_bin: bin,
          sku: @sku,
          merchant_principal_id: owner,
          quantity_delta: @quantity_delta,
          reason: @reason,
          note: @note,
          idempotency_key: @idempotency_key,
          adjusted_by_principal_id: @adjusted_by_principal_id,
          quantity_before: before,
          quantity_after: after
        )
      end

      Result.new(
        adjustment: adjustment,
        bin_code: bin.bin_code,
        quantity_on_hand: on_hand,
        reserved_quantity: reserved,
        replayed: false,
        error: nil
      )
    rescue ActiveRecord::RecordNotFound
      failure(STOCK_NOT_FOUND)
    rescue OwnerlessStock
      failure(STOCK_HAS_NO_OWNER)
    rescue WrongOwner
      failure(WRONG_OWNER)
    rescue WouldCutReserved
      failure(WOULD_CUT_RESERVED, on_hand: current_quantity, reserved: current_reserved)
    rescue ActiveRecord::RecordNotUnique => e
      replay_after_race(owner, e)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.is_a?(StockAdjustment) && e.record.errors.of_kind?(:idempotency_key, :taken)

      replay_after_race(owner, e)
    end

    sig { params(owner: String).returns(T.nilable(StockAdjustment)) }
    def stored_adjustment(owner)
      StockAdjustment.find_by(merchant_principal_id: owner, idempotency_key: @idempotency_key)
    end

    sig { params(owner: String, error: ActiveRecord::ActiveRecordError).returns(Result) }
    def replay_after_race(owner, error)
      adjustment = stored_adjustment(owner)
      raise error if adjustment.nil?

      replay(adjustment)
    end

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

    sig { params(adjustment: StockAdjustment).returns(Result) }
    def replay(adjustment)
      bin_code = adjustment.warehouse_bin&.bin_code
      same = adjustment.sku == @sku &&
             adjustment.quantity_delta == @quantity_delta &&
             adjustment.reason == @reason &&
             bin_code == @bin_code
      return failure(IDEMPOTENCY_KEY_CONFLICT) unless same

      inventory = BinInventory.find_by(warehouse_bin_id: adjustment.warehouse_bin_id, sku: adjustment.sku)
      Result.new(
        adjustment: adjustment,
        bin_code: bin_code,
        quantity_on_hand: inventory&.quantity.to_i,
        reserved_quantity: inventory&.reserved_quantity.to_i,
        replayed: true,
        error: nil
      )
    end

    sig { params(code: String, on_hand: Integer, reserved: Integer).returns(Result) }
    def failure(code, on_hand: 0, reserved: 0)
      Result.new(
        adjustment: nil,
        bin_code: nil,
        quantity_on_hand: on_hand,
        reserved_quantity: reserved,
        replayed: false,
        error: code
      )
    end
  end
end
