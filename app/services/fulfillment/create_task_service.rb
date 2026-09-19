# typed: strict

module Fulfillment
  class CreateTaskService < BaseService
    extend T::Sig

    class ResultData < T::Struct
      const :id, Integer
      const :order_number, String
      const :status, String
      const :same_day_cutoff_at, T.any(Time, ActiveSupport::TimeWithZone)
      const :already_created, T::Boolean
    end

    sig { returns(MerchantRepositoryInterface) }
    attr_reader :merchant_repository

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig do
      params(
        merchant_repository: MerchantRepositoryInterface,
        task_repository: FulfillmentTaskRepositoryInterface
      ).void
    end
    def initialize(
      merchant_repository: T.let(Container[:merchant_repository], MerchantRepositoryInterface),
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    )
      super()
      @merchant_repository = merchant_repository
      @task_repository = task_repository
    end

    sig { params(merchant_id: Integer, form: CreateTaskForm).returns(BaseService::Result) }
    def call(merchant_id:, form:)
      return failure(form.errors.join(", ")) unless form.valid?

      merchant = merchant_repository.find_by_id(merchant_id)
      return failure("Merchant not found") unless merchant

      existing = task_repository.find_by_order_number(merchant_id: merchant_id, order_number: form.order_number)
      return success(describe(existing, already_created: true)) if existing

      task = create_task(merchant_id: merchant_id, merchant: merchant, form: form)

      success(describe(task, already_created: false))
    end

    private

    sig do
      params(
        merchant_id: Integer,
        merchant: Merchant,
        form: CreateTaskForm
      ).returns(FulfillmentTask)
    end
    def create_task(merchant_id:, merchant:, form:)
      cutoff_at = calculate_cutoff_at(merchant.cutoff_hour || 12)

      task = task_repository.create(
        merchant_id: merchant_id,
        attributes: {
          order_number: form.order_number,
          status: "received",
          same_day_cutoff_at: cutoff_at
        }
      )

      form.lines.each do |line|
        task.fulfillment_task_lines.create!(sku: line.sku, quantity: line.quantity)
      end

      task
    end

    sig { params(task: FulfillmentTask, already_created: T::Boolean).returns(ResultData) }
    def describe(task, already_created:)
      ResultData.new(
        id: task.id,
        order_number: T.must(task.order_number),
        status: T.must(task.status),
        same_day_cutoff_at: T.must(task.same_day_cutoff_at),
        already_created: already_created
      )
    end

    sig { params(cutoff_hour: Integer).returns(Time) }
    def calculate_cutoff_at(cutoff_hour)
      today_cutoff = Time.current.change(hour: cutoff_hour, min: 0, sec: 0)

      Time.current <= today_cutoff ? today_cutoff : today_cutoff + 1.day
    end
  end
end
