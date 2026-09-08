# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/fulfillment_pb"

module Inventory
  class ReserveStockService
    extend T::Sig

    SKU_NOT_STOCKED = "SKU_NOT_STOCKED"
    INSUFFICIENT_STOCK = "INSUFFICIENT_STOCK"
    RESERVATION_RELEASED = "STOCK_RESERVATION_RELEASED"
    QUANTITY_MISMATCH = "RESERVATION_QUANTITY_MISMATCH"

    sig do
      params(merchant: Merchant, order_number: String, sku: String, quantity: Integer).void
    end
    def initialize(merchant:, order_number:, sku:, quantity:)
      @merchant = merchant
      @order_number = order_number
      @sku = sku
      @quantity = quantity
    end

    sig { returns(StepOutcome) }
    def call
      existing = locked_reservation
      return settle(existing) if existing

      reservation = T.let(nil, T.nilable(StockReservation))
      begin
        StockReservation.transaction(requires_new: true) do
          reservation = StockReservation.create!(
            merchant: @merchant, order_number: @order_number, sku: @sku, quantity: @quantity
          )
        end
      rescue ActiveRecord::RecordNotUnique
        return settle(locked_reservation)
      rescue ActiveRecord::LockWaitTimeout
        raise LedgerTimeout
      end

      apply(T.must(reservation))
    end

    private

    sig { returns(T.nilable(StockReservation)) }
    def locked_reservation
      StockReservation.lock("FOR UPDATE")
                      .find_by(merchant_id: @merchant.id, order_number: @order_number, sku: @sku)
    rescue ActiveRecord::LockWaitTimeout
      raise LedgerTimeout
    end

    sig { params(reservation: T.nilable(StockReservation)).returns(StepOutcome) }
    def settle(reservation)
      return refuse(RESERVATION_RELEASED, "no reservation exists for that order and sku") if reservation.nil?

      unless reservation.held?
        return refuse(RESERVATION_RELEASED, "that reservation was already released")
      end

      unless reservation.quantity == @quantity
        return refuse(
          QUANTITY_MISMATCH,
          "that order and sku already hold #{reservation.quantity} units, not #{@quantity}"
        )
      end

      StepOutcome.new(
        message: Fulfillment::V1::ReserveStockResponse.new(
          success: true,
          bin_location: bin_code_for(reservation),
          remaining_available: available_for_sku
        ),
        commit: true,
        applied: false
      )
    end

    sig { params(reservation: StockReservation).returns(StepOutcome) }
    def apply(reservation)
      bins = BinInventory.where(sku: @sku).order(:id).lock("FOR UPDATE").to_a
      return refuse(SKU_NOT_STOCKED, "no bin in this warehouse carries #{@sku}") if bins.empty?

      bin = bins.find { |candidate| candidate.available_quantity >= @quantity }
      if bin.nil?
        largest = bins.map(&:available_quantity).max.to_i

        return refuse(
          INSUFFICIENT_STOCK,
          "no single bin can cover #{@quantity} units of #{@sku}; " \
          "the largest single bin holds #{largest}",
          remaining: largest
        )
      end

      reservation.update!(bin_inventory: bin)
      bin.update!(reserved_quantity: bin.reserved_quantity.to_i + @quantity)

      StepOutcome.new(
        message: Fulfillment::V1::ReserveStockResponse.new(
          success: true,
          bin_location: bin_code_of(bin),
          remaining_available: bins.sum(&:available_quantity)
        ),
        commit: true,
        applied: true
      )
    end

    sig { params(reservation: StockReservation).returns(String) }
    def bin_code_for(reservation)
      bin = reservation.bin_inventory || BinInventory.where(sku: @sku).order(:id).first
      bin.nil? ? "N/A" : bin_code_of(bin)
    end

    sig { params(bin: BinInventory).returns(String) }
    def bin_code_of(bin)
      bin.warehouse_bin&.bin_code.presence || "N/A"
    end

    sig { returns(Integer) }
    def available_for_sku
      BinInventory.where(sku: @sku).to_a.sum(&:available_quantity)
    end

    sig { params(code: String, text: String, remaining: Integer).returns(StepOutcome) }
    def refuse(code, text, remaining: 0)
      StepOutcome.new(
        message: Fulfillment::V1::ReserveStockResponse.new(
          success: false,
          bin_location: "N/A",
          remaining_available: remaining,
          error: Common::V1::ErrorDetail.new(error_code: code, message: text)
        ),
        commit: false
      )
    end
  end
end
