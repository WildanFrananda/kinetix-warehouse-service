# typed: strict
# frozen_string_literal: true

module Inventory
  class AbandonedHoldReport
    extend T::Sig

    DEFAULT_AGE_HOURS = 24
    MIN_AGE_HOURS = 1
    MAX_AGE_HOURS = 8_760

    sig { returns(Integer) }
    def self.age_hours
      ENV.fetch("WAREHOUSE_ABANDONED_HOLD_HOURS", DEFAULT_AGE_HOURS)
         .to_i
         .clamp(MIN_AGE_HOURS, MAX_AGE_HOURS)
    end

    sig { params(older_than_hours: Integer).void }
    def initialize(older_than_hours: AbandonedHoldReport.age_hours)
      @older_than_hours = older_than_hours
      @rows = T.let(nil, T.nilable(T::Array[StockReservation]))
    end

    sig { returns(Integer) }
    def older_than_hours
      @older_than_hours
    end

    sig { returns(T::Array[StockReservation]) }
    def rows
      @rows ||= StockReservation
                .held_before(@older_than_hours.hours.ago)
                .order(:created_at)
                .to_a
    end

    sig { returns(Integer) }
    def units
      rows.sum { |reservation| reservation.quantity.to_i }
    end

    sig { returns(Integer) }
    def call
      rows.each { |reservation| log_hold(reservation) }
      log_summary
      rows.size
    end

    private

    sig { params(reservation: StockReservation).void }
    def log_hold(reservation)
      Rails.logger.error(
        "stock.idem abandoned_hold reservation_id=#{reservation.id} " \
        "order_number=#{reservation.order_number} sku=#{reservation.sku} " \
        "merchant_id=#{reservation.merchant_id} quantity=#{reservation.quantity} " \
        "bin_inventory_id=#{reservation.bin_inventory_id || '-'} " \
        "age_hours=#{age_hours_of(reservation)} — held with no release for longer than " \
        "#{@older_than_hours}h. Check the owning saga before reclaiming: " \
        "rake stock:release_hold[#{reservation.id}]"
      )
    end

    sig { void }
    def log_summary
      text = "stock.idem abandoned_hold_summary count=#{rows.size} units=#{units} " \
             "older_than_hours=#{@older_than_hours}"

      rows.empty? ? Rails.logger.info(text) : Rails.logger.error(text)
    end

    sig { params(reservation: StockReservation).returns(Integer) }
    def age_hours_of(reservation)
      created = reservation.created_at
      return 0 if created.nil?

      ((Time.current - created) / 3_600).floor
    end
  end
end
