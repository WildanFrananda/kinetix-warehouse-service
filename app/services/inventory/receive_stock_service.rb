# typed: strict
# frozen_string_literal: true

module Inventory
  class ReceiveStockService
    extend T::Sig

    class WrongOwner < StandardError; end

    BIN_NOT_FOUND = "BIN_NOT_FOUND"
    INVALID_QUANTITY = "INVALID_QUANTITY"
    INVALID_SKU = "INVALID_SKU"
    INVALID_IDEMPOTENCY_KEY = "INVALID_IDEMPOTENCY_KEY"
    INVALID_BIN_CODE = "INVALID_BIN_CODE"
    INVALID_NOTE = "INVALID_NOTE"
    STOCK_LIMIT_EXCEEDED = "STOCK_LIMIT_EXCEEDED"
    INVALID_MERCHANT_PRINCIPAL = "INVALID_MERCHANT_PRINCIPAL"
    UNKNOWN_MERCHANT = "UNKNOWN_MERCHANT"
    IDEMPOTENCY_KEY_CONFLICT = "IDEMPOTENCY_KEY_CONFLICT"
    WRONG_OWNER = "WRONG_OWNER"

    QUANTITIES = T.let(1..BinInventory::MAX_QUANTITY, T::Range[Integer])

    class Result < T::Struct
      const :receipt, T.nilable(StockReceipt)
      const :bin_code, T.nilable(String)
      const :quantity_on_hand, Integer
      const :replayed, T::Boolean
      const :error, T.nilable(String)
    end

    sig do
      params(
        bin_code: String,
        sku: String,
        quantity: T.nilable(Integer),
        idempotency_key: String,
        received_by_principal_id: String,
        merchant_principal_id: String,
        note: T.nilable(String),
        resolve_merchant_service: Merchants::ResolveService
      ).void
    end
    def initialize(
      bin_code:,
      sku:,
      quantity:,
      idempotency_key:,
      received_by_principal_id:,
      merchant_principal_id:,
      note: nil,
      resolve_merchant_service: T.let(Container[:resolve_merchant_service], Merchants::ResolveService)
    )
      @bin_code = bin_code
      @sku = sku
      @quantity = quantity
      @idempotency_key = idempotency_key
      @received_by_principal_id = received_by_principal_id
      @merchant_principal_id = merchant_principal_id
      @note = note
      @resolve_merchant_service = resolve_merchant_service
    end

    sig { returns(Result) }
    def call
      quantity = @quantity
      return failure(INVALID_QUANTITY) if quantity.nil? || !QUANTITIES.cover?(quantity)
      return failure(INVALID_IDEMPOTENCY_KEY) unless StockIdentifiers.idempotency_key?(@idempotency_key)

      owner = Kinetix::PrincipalId.canonical(@merchant_principal_id)
      return failure(INVALID_MERCHANT_PRINCIPAL) if owner.nil?
      return failure(INVALID_SKU) unless StockIdentifiers.sku?(@sku)
      return failure(INVALID_BIN_CODE) unless StockIdentifiers.bin_code?(@bin_code)
      return failure(INVALID_NOTE) unless note_fits?

      existing = stored_receipt(owner)
      return replay(existing) if existing

      standing = @resolve_merchant_service.call(principal_id: owner)
      return failure(UNKNOWN_MERCHANT) if standing.nil?

      bin = WarehouseBin.find_by(bin_code: @bin_code)
      return failure(BIN_NOT_FOUND) if bin.nil?

      book(bin, T.must(standing.merchant.principal_id), quantity)
    end

    private

    sig { params(bin: WarehouseBin, owner: String, quantity: Integer).returns(Result) }
    def book(bin, owner, quantity)
      receipt = T.let(nil, T.nilable(StockReceipt))
      on_hand = T.let(0, Integer)

      ActiveRecord::Base.transaction do
        BinInventory.insert_all(
          [
            {
              warehouse_bin_id: bin.id,
              sku: @sku,
              quantity: 0,
              reserved_quantity: 0,
              merchant_principal_id: owner
            }
          ],
          unique_by: %i[warehouse_bin_id sku]
        )
        inventory = BinInventory.lock("FOR UPDATE").find_by!(warehouse_bin_id: bin.id, sku: @sku)

        recorded_owner = inventory.merchant_principal_id
        raise WrongOwner if recorded_owner.present? && recorded_owner != owner

        inventory.update!(merchant_principal_id: owner) if recorded_owner.blank?

        after = inventory.quantity.to_i + quantity
        raise StockLimitExceeded if after > BinInventory::MAX_QUANTITY

        inventory.update!(quantity: after)
        on_hand = after

        receipt = StockReceipt.create!(
          warehouse_bin: bin,
          sku: @sku,
          quantity: quantity,
          idempotency_key: @idempotency_key,
          received_by_principal_id: @received_by_principal_id,
          merchant_principal_id: owner,
          note: @note
        )
      end

      Result.new(receipt: receipt, bin_code: bin.bin_code, quantity_on_hand: on_hand, replayed: false, error: nil)
    rescue WrongOwner
      failure(WRONG_OWNER)
    rescue StockLimitExceeded
      failure(STOCK_LIMIT_EXCEEDED)
    rescue ActiveRecord::RecordNotUnique => e
      replay_after_race(owner, e)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.is_a?(StockReceipt) && e.record.errors.of_kind?(:idempotency_key, :taken)

      replay_after_race(owner, e)
    end

    sig { returns(T::Boolean) }
    def note_fits?
      note = @note
      note.nil? || note.length <= StockReceipt::MAX_NOTE_LENGTH
    end

    sig { params(owner: String).returns(T.nilable(StockReceipt)) }
    def stored_receipt(owner)
      StockReceipt.find_by(merchant_principal_id: owner, idempotency_key: @idempotency_key)
    end

    sig { params(owner: String, error: ActiveRecord::ActiveRecordError).returns(Result) }
    def replay_after_race(owner, error)
      receipt = stored_receipt(owner)
      raise error if receipt.nil?

      replay(receipt)
    end

    sig { params(receipt: StockReceipt).returns(Result) }
    def replay(receipt)
      bin_code = receipt.warehouse_bin&.bin_code
      same = receipt.sku == @sku && receipt.quantity == @quantity && bin_code == @bin_code
      return failure(IDEMPOTENCY_KEY_CONFLICT) unless same

      inventory = BinInventory.find_by(warehouse_bin_id: receipt.warehouse_bin_id, sku: receipt.sku)
      Result.new(
        receipt: receipt,
        bin_code: bin_code,
        quantity_on_hand: inventory&.quantity.to_i,
        replayed: true,
        error: nil
      )
    end

    sig { params(code: String).returns(Result) }
    def failure(code)
      Result.new(receipt: nil, bin_code: nil, quantity_on_hand: 0, replayed: false, error: code)
    end
  end
end
