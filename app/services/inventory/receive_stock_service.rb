# typed: strict
# frozen_string_literal: true

module Inventory
  class ReceiveStockService
    extend T::Sig

    class WrongOwner < StandardError; end

    BIN_NOT_FOUND = "BIN_NOT_FOUND"
    INVALID_QUANTITY = "INVALID_QUANTITY"
    WRONG_OWNER = "WRONG_OWNER"

    class Result < T::Struct
      const :receipt, T.nilable(StockReceipt)
      const :quantity_on_hand, Integer
      const :replayed, T::Boolean
      const :error, T.nilable(String)
    end

    sig do
      params(
        bin_code: String,
        sku: String,
        quantity: Integer,
        idempotency_key: String,
        received_by_principal_id: String,
        merchant_principal_id: String,
        note: T.nilable(String)
      ).void
    end
    def initialize(bin_code:, sku:, quantity:, idempotency_key:, received_by_principal_id:,
                   merchant_principal_id:, note: nil)
      @bin_code = bin_code
      @sku = sku
      @quantity = quantity
      @idempotency_key = idempotency_key
      @received_by_principal_id = received_by_principal_id
      @merchant_principal_id = merchant_principal_id
      @note = note
    end

    sig { returns(Result) }
    def call
      return failure(INVALID_QUANTITY) if @quantity <= 0
      return failure(WRONG_OWNER) if @merchant_principal_id.to_s.empty?

      existing = StockReceipt.find_by(idempotency_key: @idempotency_key)
      return replay(existing) if existing

      bin = WarehouseBin.find_by(bin_code: @bin_code)
      return failure(BIN_NOT_FOUND) if bin.nil?

      receipt = T.let(nil, T.nilable(StockReceipt))
      on_hand = T.let(0, Integer)

      ActiveRecord::Base.transaction do
        inventory = BinInventory.lock("FOR UPDATE").find_by(warehouse_bin_id: bin.id, sku: @sku)
        inventory ||= BinInventory.create!(
          warehouse_bin: bin, sku: @sku, quantity: 0, reserved_quantity: 0,
          merchant_principal_id: @merchant_principal_id
        )

        owner = inventory.merchant_principal_id
        if owner.present? && owner != @merchant_principal_id
          raise WrongOwner
        end

        inventory.update!(merchant_principal_id: @merchant_principal_id) if owner.blank?

        inventory.update!(quantity: inventory.quantity.to_i + @quantity)
        on_hand = inventory.quantity.to_i

        receipt = StockReceipt.create!(
          warehouse_bin: bin,
          sku: @sku,
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          received_by_principal_id: @received_by_principal_id,
          merchant_principal_id: @merchant_principal_id,
          note: @note
        )
      end

      Result.new(receipt: receipt, quantity_on_hand: on_hand, replayed: false, error: nil)
    rescue WrongOwner
      failure(WRONG_OWNER)
    rescue ActiveRecord::RecordNotUnique
      replay(StockReceipt.find_by(idempotency_key: @idempotency_key))
    end

    private

    sig { params(receipt: T.nilable(StockReceipt)).returns(Result) }
    def replay(receipt)
      return failure(BIN_NOT_FOUND) if receipt.nil?

      inventory = BinInventory.find_by(warehouse_bin_id: receipt.warehouse_bin_id, sku: receipt.sku)
      Result.new(
        receipt: receipt,
        quantity_on_hand: inventory&.quantity.to_i,
        replayed: true,
        error: nil
      )
    end

    sig { params(code: String).returns(Result) }
    def failure(code)
      Result.new(receipt: nil, quantity_on_hand: 0, replayed: false, error: code)
    end
  end
end
