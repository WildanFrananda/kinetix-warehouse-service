# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/fulfillment_pb"

module Inventory
  class ReleaseStockService
    extend T::Sig

    sig { params(merchant: Merchant, order_number: String, sku: String).void }
    def initialize(merchant:, order_number:, sku:)
      @merchant = merchant
      @order_number = order_number
      @sku = sku
    end

    sig { returns(StepOutcome) }
    def call
      reservation = locked_reservation
      reservation = tombstone if reservation.nil?
      return released(already: true) if reservation.nil?

      return released(already: true) unless reservation.held?

      give_back(reservation)
    end

    private

    sig { returns(T.nilable(StockReservation)) }
    def locked_reservation
      StockReservation.lock("FOR UPDATE")
                      .find_by(merchant_id: @merchant.id, order_number: @order_number, sku: @sku)
    rescue ActiveRecord::LockWaitTimeout
      raise LedgerTimeout
    end

    sig { returns(T.nilable(StockReservation)) }
    def tombstone
      StockReservation.transaction(requires_new: true) do
        StockReservation.create!(
          merchant: @merchant, order_number: @order_number, sku: @sku,
          quantity: 0, released_at: Time.current
        )
      end

      Rails.logger.error(
        "stock.idem orphan_release order_number=#{@order_number} sku=#{@sku} " \
        "merchant_id=#{@merchant.id} — released stock that was never reserved; a tombstone now " \
        "blocks a late reserve for this pair (request_id=#{Kinetix::RequestId.current || '-'})"
      )
      nil
    rescue ActiveRecord::RecordNotUnique
      locked_reservation
    rescue ActiveRecord::LockWaitTimeout
      raise LedgerTimeout
    end

    sig { params(reservation: StockReservation).returns(StepOutcome) }
    def give_back(reservation)
      bin = locked_bin(reservation)

      if bin.nil?
        Rails.logger.error(
          "stock.idem release_bin_missing order_number=#{@order_number} sku=#{@sku} " \
          "bin_inventory_id=#{reservation.bin_inventory_id || '-'} — nothing left to credit " \
          "(request_id=#{Kinetix::RequestId.current || '-'})"
        )
        reservation.update!(released_at: Time.current)
        return released(already: false)
      end

      taken = creditable(reservation, bin)
      bin.update!(reserved_quantity: bin.reserved_quantity.to_i - taken) if taken.positive?
      reservation.update!(released_at: Time.current)

      released(already: false, applied: taken.positive?)
    end

    sig { params(reservation: StockReservation, bin: BinInventory).returns(Integer) }
    def creditable(reservation, bin)
      wanted = reservation.quantity.to_i
      reserved = bin.reserved_quantity.to_i
      return [ wanted, reserved ].min if reservation.bin_inventory_id

      claimed = StockReservation.held.where(bin_inventory_id: bin.id).sum(:quantity).to_i
      taken = [ wanted, reserved - claimed ].min
      taken = 0 if taken.negative?

      log_guessed_credit(reservation, bin, wanted, taken)
      taken
    end

    sig do
      params(reservation: StockReservation, bin: BinInventory, wanted: Integer, taken: Integer).void
    end
    def log_guessed_credit(reservation, bin, wanted, taken)
      Rails.logger.error(
        "stock.idem release_bin_guessed reservation_id=#{reservation.id} " \
        "order_number=#{@order_number} sku=#{@sku} bin_inventory_id=#{bin.id} wanted=#{wanted} " \
        "credited=#{taken} — this ledger row predates bin_inventory_id, so the bin credited is the " \
        "lowest-id bin for the sku and not necessarily the one the reserve debited. The credit is " \
        "capped at what no live hold on that bin claims. If credited < wanted the difference is " \
        "stranded on another bin and runbook query 2 will report it as drift " \
        "(request_id=#{Kinetix::RequestId.current || '-'})"
      )
    end

    sig { params(reservation: StockReservation).returns(T.nilable(BinInventory)) }
    def locked_bin(reservation)
      id = reservation.bin_inventory_id
      return BinInventory.lock("FOR UPDATE").find_by(id: id) if id

      BinInventory.where(sku: @sku).order(:id).lock("FOR UPDATE").first
    end

    sig { params(already: T::Boolean, applied: T::Boolean).returns(StepOutcome) }
    def released(already:, applied: false)
      StepOutcome.new(
        message: Fulfillment::V1::ReleaseStockResponse.new(
          success: true,
          already_released: already,
          remaining_available: available_for_sku
        ),
        commit: true,
        applied: applied
      )
    end

    sig { returns(Integer) }
    def available_for_sku
      BinInventory.where(sku: @sku).to_a.sum(&:available_quantity)
    end
  end
end
