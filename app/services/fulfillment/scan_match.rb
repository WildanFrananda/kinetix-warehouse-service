# typed: strict

module Fulfillment
  class ScanMatch < T::Struct
    extend T::Sig

    SKU = "sku"
    ORDER_NUMBER = "order_number"
    TRACKING_NUMBER = "tracking_number"

    const :kind, String
    const :code, String
    const :line, T.nilable(FulfillmentTaskLine)

    sig { params(task: FulfillmentTask, scanned: String).returns(T.nilable(ScanMatch)) }
    def self.find(task, scanned)
      lines = task.fulfillment_task_lines.select { |candidate| candidate.sku.to_s.casecmp?(scanned) }
      line = lines.find { |candidate| candidate.scanned_at.nil? } || lines.first
      return new(kind: SKU, code: line.sku.to_s, line: line) if line

      order_number = task.order_number.to_s
      return new(kind: ORDER_NUMBER, code: order_number, line: nil) if order_number.casecmp?(scanned)

      tracking = task.shipping_label&.awb_number
      return new(kind: TRACKING_NUMBER, code: tracking, line: nil) if tracking && tracking.casecmp?(scanned)

      nil
    end
  end
end
