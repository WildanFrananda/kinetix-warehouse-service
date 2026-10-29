# typed: strict

module Inventory
  class BinSummary < T::Struct
    extend T::Sig

    const :id, Integer
    const :bin_code, String
    const :zone, String
    const :shelf_level, Integer
    const :sku_count, Integer
    const :quantity, Integer
    const :reserved_quantity, Integer
    const :updated_at, ActiveSupport::TimeWithZone

    sig { params(bin: WarehouseBin).returns(BinSummary) }
    def self.of(bin)
      new(
        id: bin.id,
        bin_code: bin.bin_code,
        zone: bin.zone,
        shelf_level: bin.shelf_level,
        sku_count: Integer(bin[:sku_count]),
        quantity: Integer(bin[:total_quantity]),
        reserved_quantity: Integer(bin[:total_reserved_quantity]),
        updated_at: bin.updated_at
      )
    end
  end
end
