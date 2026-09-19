# typed: strict

module Fulfillment
  class TaskQueueService < BaseService
    extend T::Sig

    class TaskLineData < T::Struct
      const :sku, String
      const :quantity, Integer
      const :bin_location, String
    end

    class TaskCardData < T::Struct
      const :id, Integer
      const :order_number, String
      const :status, String
      const :same_day_cutoff_at, T.any(Time, ActiveSupport::TimeWithZone)
      const :created_at, T.any(Time, ActiveSupport::TimeWithZone)
      const :tracking_number, T.nilable(String)
      const :sla_urgency, String
      const :lines, T::Array[TaskLineData]
    end

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig { params(task_repository: FulfillmentTaskRepositoryInterface).void }
    def initialize(
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    )
      super()
      @task_repository = task_repository
    end

    sig { params(merchant_id: Integer).returns(BaseService::Result) }
    def call(merchant_id:)
      now = Time.current

      cards = task_repository.due_today(merchant_id: merchant_id).map do |task|
        build_card(task, now)
      end

      success(cards)
    end

    private

    sig { params(task: FulfillmentTask, now: Time).returns(TaskCardData) }
    def build_card(task, now)
      cutoff = T.must(task.same_day_cutoff_at)
      label = T.must(task.shipping_label)&.awb_number if task.shipping_label

      TaskCardData.new(
        id: task.id,
        order_number: T.must(task.order_number),
        status: T.must(task.status),
        same_day_cutoff_at: cutoff,
        created_at: task.created_at,
        tracking_number: label,
        sla_urgency: urgency_for(cutoff, now),
        lines: task.fulfillment_task_lines.map { |line| build_line(line) }
      )
    end

    sig { params(line: FulfillmentTaskLine).returns(TaskLineData) }
    def build_line(line)
      raw_bin = T.cast(line.read_attribute(:bin_location), T.nilable(String))

      TaskLineData.new(
        sku: T.must(line.sku),
        quantity: T.must(line.quantity),
        # Empty rather than a made-up shelf. The old default was the literal "Rak A-01, Bin 01", which
        # sent a picker to a real bin that had nothing to do with the parcel.
        bin_location: raw_bin.presence || ""
      )
    end

    sig { params(cutoff: T.any(Time, ActiveSupport::TimeWithZone), now: Time).returns(String) }
    def urgency_for(cutoff, now)
      return "overdue" if cutoff < now
      return "due_soon" if cutoff < now + 2.hours

      "due_today"
    end
  end
end
