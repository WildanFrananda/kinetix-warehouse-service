# typed: strict

module Api
  module V1
    class FulfillmentTasksController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStringParams

      TASK_NOT_FOUND = "Fulfillment task not found"

      sig { void }
      def index
        merchant = require_api_merchant!
        return if merchant.nil?

        order_number = params[:order_number]
        unless order_number.is_a?(String) && string_problem(order_number).nil? && !order_number.strip.empty?
          render(
            json: { error: "order_number is required: name the order whose task you are looking for" },
            status: :bad_request
          )
          return
        end

        service = T.let(Container[:task_lookup_service], Fulfillment::TaskLookupService)
        result = service.call(merchant_id: merchant.id, order_number: order_number.strip)

        render_result(result)
      end

      sig { void }
      def queue
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:task_queue_service], Fulfillment::TaskQueueService)
        result = service.call(merchant_id: merchant.id)

        render_result(result)
      end

      sig { void }
      def update_status
        merchant = require_api_merchant!
        return if merchant.nil?

        task_id = require_task_id!
        return if task_id.nil?
        return if refuse_unusable_strings(%i[status], coded: false)

        service = T.let(Container[:advance_task_service], Fulfillment::AdvanceTaskService)
        result = service.call(
          merchant_id: merchant.id,
          task_id: task_id,
          new_status: string_param(:status).to_s
        )

        render_result(result)
      end

      sig { void }
      def generate_label
        merchant = require_api_merchant!
        return if merchant.nil?

        task_id = require_task_id!
        return if task_id.nil?

        service = T.let(Container[:generate_shipping_label_service], Labels::GenerateShippingLabelService)
        result = service.call(merchant_id: merchant.id, fulfillment_task_id: task_id)

        render_result(result)
      end

      sig { void }
      def verify_scan
        merchant = require_api_merchant!
        return if merchant.nil?

        task_id = require_task_id!
        return if task_id.nil?
        return if refuse_unusable_strings(%i[scanned_code], coded: false)

        scanned_code = string_param(:scanned_code).to_s
        limit = Fulfillment::VerifyScanService::MAX_CODE_LENGTH
        if scanned_code.length > limit
          render json: { error: "scanned_code must be at most #{limit} characters" }, status: :unprocessable_content
          return
        end

        service = T.let(Container[:verify_scan_service], Fulfillment::VerifyScanService)
        result = service.call(merchant_id: merchant.id, task_id: task_id, scanned_code: scanned_code)

        render_result(result)
      end

      private

      sig { returns(T.nilable(Integer)) }
      def require_task_id!
        id = Kinetix::IntegerParam.id(params[:id])
        render(json: { error: TASK_NOT_FOUND }, status: :not_found) if id.nil?

        id
      end

      sig { params(result: BaseService::Result).void }
      def render_result(result)
        if result.success?
          render(json: result.data)
        else
          render(
            json: { error: result.error },
            status: result.not_found? ? :not_found : :unprocessable_content
          )
        end
      end
    end
  end
end
