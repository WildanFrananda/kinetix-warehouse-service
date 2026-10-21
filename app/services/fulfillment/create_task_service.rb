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

    sig { returns(StockReservationRepositoryInterface) }
    attr_reader :reservation_repository

    sig { returns(ActiveSupport::TimeZone) }
    attr_reader :time_zone

    sig do
      params(
        merchant_repository: MerchantRepositoryInterface,
        task_repository: FulfillmentTaskRepositoryInterface,
        reservation_repository: StockReservationRepositoryInterface,
        time_zone: ActiveSupport::TimeZone
      ).void
    end
    def initialize(
      merchant_repository: T.let(Container[:merchant_repository], MerchantRepositoryInterface),
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface),
      reservation_repository: T.let(Container[:stock_reservation_repository], StockReservationRepositoryInterface),
      time_zone: T.let(Rails.configuration.x.platform_time_zone, ActiveSupport::TimeZone)
    )
      super()
      @merchant_repository = merchant_repository
      @task_repository = task_repository
      @reservation_repository = reservation_repository
      @time_zone = time_zone
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
      cutoff_at = calculate_cutoff_at(merchant.cutoff_hour)
      bins = reservation_repository.held_bin_codes(merchant_id: merchant_id, order_number: form.order_number)

      task_repository.create(
        merchant_id: merchant_id,
        attributes: {
          order_number: form.order_number,
          status: "received",
          same_day_cutoff_at: cutoff_at
        },
        lines: form.lines.map do |line|
          { sku: line.sku, quantity: line.quantity, bin_location: bins[line.sku] }
        end
      )
    end

    sig { params(task: FulfillmentTask, already_created: T::Boolean).returns(ResultData) }
    def describe(task, already_created:)
      ResultData.new(
        id: task.id,
        order_number: T.must(task.order_number),
        status: task.status,
        same_day_cutoff_at: T.must(task.same_day_cutoff_at),
        already_created: already_created
      )
    end

    sig { params(cutoff_hour: Integer).returns(ActiveSupport::TimeWithZone) }
    def calculate_cutoff_at(cutoff_hour)
      now = time_zone.now
      today_cutoff = now.change(hour: cutoff_hour, min: 0, sec: 0)

      now <= today_cutoff ? today_cutoff : today_cutoff + 1.day
    end
  end
end
