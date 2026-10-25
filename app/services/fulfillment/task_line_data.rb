# typed: strict

module Fulfillment
  class TaskLineData < T::Struct
    extend T::Sig

    const :sku, String
    const :quantity, Integer
    const :bin_location, String
    const :scanned, T::Boolean

    sig { params(line: FulfillmentTaskLine).returns(TaskLineData) }
    def self.of(line)
      new(
        sku: T.must(line.sku),
        quantity: T.must(line.quantity),
        bin_location: line.bin_location.to_s,
        scanned: !line.scanned_at.nil?
      )
    end
  end
end
