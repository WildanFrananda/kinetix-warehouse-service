# typed: strict

module Fulfillment
  class TaskQueueService < BaseService
    extend T::Sig

    PACKED = "packed"

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

      cards = task_repository.open_work(merchant_id: merchant_id).map do |task|
        build_card(task, now)
      end

      success(cards)
    end

    private

    sig { params(task: FulfillmentTask, now: ActiveSupport::TimeWithZone).returns(TaskCardData) }
    def build_card(task, now)
      cutoff = T.must(task.same_day_cutoff_at)

      TaskCardData.new(
        id: task.id,
        order_number: T.must(task.order_number),
        status: task.status,
        same_day_cutoff_at: cutoff,
        created_at: task.created_at,
        tracking_number: task.shipping_label&.awb_number,
        sla_urgency: task.status == PACKED ? PACKED : urgency_for(cutoff, now),
        lines: task.fulfillment_task_lines.map { |line| TaskLineData.of(line) }
      )
    end

    sig { params(cutoff: ActiveSupport::TimeWithZone, now: ActiveSupport::TimeWithZone).returns(String) }
    def urgency_for(cutoff, now)
      return "overdue" if cutoff < now
      return "due_soon" if cutoff < now + 2.hours

      "due_today"
    end
  end
end
