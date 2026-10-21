# typed: strict

class StockReservationRepository < BaseRepository
  include StockReservationRepositoryInterface
  extend T::Sig

  sig { void }
  def initialize
    super(StockReservation)
  end

  sig { override.params(merchant_id: Integer, order_number: String).returns(T::Hash[String, String]) }
  def held_bin_codes(merchant_id:, order_number:)
    rows = model
      .joins(bin_inventory: :warehouse_bin)
      .where(merchant_id: merchant_id, order_number: order_number, released_at: nil)
      .pluck(:sku, "warehouse_bins.bin_code")

    T.cast(rows, T::Array[[ String, String ]]).to_h
  end
end
