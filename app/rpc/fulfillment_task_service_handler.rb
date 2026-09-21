# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/task_services_pb"

module Rpc
  class FulfillmentTaskServiceHandler < Fulfillment::V1::FulfillmentTaskService::Service
    extend T::Sig

    sig { void }
    def initialize
      super
    end

    sig do
      params(
        req: Fulfillment::V1::CreateFulfillmentTaskRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::CreateFulfillmentTaskResponse)
    end
    def create_fulfillment_task(req, _call)
      merchant = merchant_for(req.merchant_principal_id)
      return refuse_create("UNKNOWN_MERCHANT", "no merchant in this warehouse is linked to that principal") unless merchant

      form = Fulfillment::CreateTaskForm.new(
        order_number: req.order_number,
        lines: req.lines.map { |line| Fulfillment::CreateTaskForm::LineInput.new(sku: line.sku, quantity: line.quantity) }
      )

      service = T.let(Container[:create_task_service], Fulfillment::CreateTaskService)
      result = service.call(merchant_id: T.must(merchant.id), form: form)

      return refuse_create("VALIDATION_FAILED", result.error.to_s) unless result.success?

      data = T.cast(result.data, Fulfillment::CreateTaskService::ResultData)

      Fulfillment::V1::CreateFulfillmentTaskResponse.new(
        success: true,
        task_id: data.id.to_s,
        already_created: data.already_created
      )
    end

    sig do
      params(
        req: Fulfillment::V1::CancelFulfillmentTaskRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::CancelFulfillmentTaskResponse)
    end
    def cancel_fulfillment_task(req, _call)
      merchant = merchant_for(req.merchant_principal_id)
      return refuse_cancel("UNKNOWN_MERCHANT", "no merchant in this warehouse is linked to that principal") unless merchant

      task_id = Integer(req.task_id, exception: false)
      return refuse_cancel("UNKNOWN_TASK", "task_id is not a number this warehouse could have issued") unless task_id

      repository = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
      task = repository.find_by_id(merchant_id: T.must(merchant.id), id: task_id)
      return refuse_cancel("UNKNOWN_TASK", "no task with that id belongs to this merchant") unless task

      return already_cancelled(task) if task.status == "cancelled"

      repository.update_status(merchant_id: T.must(merchant.id), task_id: task_id, status: "cancelled")

      Fulfillment::V1::CancelFulfillmentTaskResponse.new(success: true, already_cancelled: false)
    end

    sig do
      params(
        req: Fulfillment::V1::RecordCourierAwbRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::RecordCourierAwbResponse)
    end
    def record_courier_awb(req, _call)
      merchant = merchant_for(req.merchant_principal_id)
      return refuse_awb("UNKNOWN_MERCHANT", "no merchant in this warehouse is linked to that principal") unless merchant

      return refuse_awb("BLANK_AWB", "awb_number is required: a parcel is not labelled with nothing") if req.awb_number.strip.empty?

      task_id = Integer(req.fulfillment_task_id, exception: false)
      return refuse_awb("UNKNOWN_TASK", "fulfillment_task_id is not a number this warehouse could have issued") unless task_id

      repository = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
      task = repository.find_by_id(merchant_id: T.must(merchant.id), id: task_id)
      return refuse_awb("UNKNOWN_TASK", "no task with that id belongs to this merchant") unless task

      existing = task.shipping_label

      if existing&.awb_number == req.awb_number
        return Fulfillment::V1::RecordCourierAwbResponse.new(accepted: true, already_recorded: true)
      end

      if existing
        existing.update!(awb_number: req.awb_number)
      else
        task.create_shipping_label!(awb_number: req.awb_number, reprint_count: 0)
      end

      Fulfillment::V1::RecordCourierAwbResponse.new(accepted: true, already_recorded: false)
    rescue ActiveRecord::RecordInvalid => e
      refuse_awb("AWB_REFUSED", e.message)
    end

    private

    sig { params(principal_id: String).returns(T.nilable(Merchant)) }
    def merchant_for(principal_id)
      return nil if principal_id.empty?

      Merchant.find_by(principal_id: principal_id)
    end

    sig { params(task: FulfillmentTask).returns(Fulfillment::V1::CancelFulfillmentTaskResponse) }
    def already_cancelled(_task)
      Fulfillment::V1::CancelFulfillmentTaskResponse.new(success: true, already_cancelled: true)
    end

    sig { params(code: String, message: String).returns(Fulfillment::V1::CreateFulfillmentTaskResponse) }
    def refuse_create(code, message)
      Fulfillment::V1::CreateFulfillmentTaskResponse.new(
        success: false,
        task_id: "",
        already_created: false,
        error: Common::V1::ErrorDetail.new(error_code: code, message: message)
      )
    end

    sig { params(code: String, message: String).returns(Fulfillment::V1::RecordCourierAwbResponse) }
    def refuse_awb(code, message)
      Fulfillment::V1::RecordCourierAwbResponse.new(
        accepted: false,
        already_recorded: false,
        error: Common::V1::ErrorDetail.new(error_code: code, message: message)
      )
    end

    sig { params(code: String, message: String).returns(Fulfillment::V1::CancelFulfillmentTaskResponse) }
    def refuse_cancel(code, message)
      Fulfillment::V1::CancelFulfillmentTaskResponse.new(
        success: false,
        already_cancelled: false,
        error: Common::V1::ErrorDetail.new(error_code: code, message: message)
      )
    end
  end
end
