# typed: strict

module Fulfillment
  class TaskRecordData < T::Struct
    extend T::Sig

    const :id, Integer
    const :order_number, String
    const :status, String
    const :same_day_cutoff_at, T.any(Time, ActiveSupport::TimeWithZone)
    const :created_at, T.any(Time, ActiveSupport::TimeWithZone)
    const :updated_at, T.any(Time, ActiveSupport::TimeWithZone)
    const :tracking_number, T.nilable(String)
    const :label_print_count, Integer
    const :lines, T::Array[TaskLineData]

    sig { params(task: FulfillmentTask).returns(TaskRecordData) }
    def self.of(task)
      label = task.shipping_label

      new(
        id: task.id,
        order_number: T.must(task.order_number),
        status: task.status,
        same_day_cutoff_at: T.must(task.same_day_cutoff_at),
        created_at: task.created_at,
        updated_at: task.updated_at,
        tracking_number: label&.awb_number,
        label_print_count: label ? label.print_count : 0,
        lines: task.fulfillment_task_lines.map { |line| TaskLineData.of(line) }
      )
    end
  end
end
