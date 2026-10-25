# typed: strict

module Api
  module V1
    class ReturnsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStringParams

      sig { void }
      def create
        merchant = require_api_merchant!
        return if merchant.nil?

        task = find_task(merchant, Kinetix::IntegerParam.id(params[:fulfillment_task_id]))
        return if task.nil?
        return if refuse_unusable_strings(%i[reason], coded: false)

        reason = string_param(:reason).to_s
        if reason.strip.empty?
          render json: { error: "Reason cannot be blank" }, status: :unprocessable_content
          return
        end

        relay = T.let(Container[:order_grpc_client], Order::ReturnRelay)
        result = relay.open_return(
          merchant_principal_id: T.must(merchant.principal_id),
          order_number: T.must(task.order_number),
          reason: reason
        )

        if result[:success]
          render json: {
            return_number: result[:return_number],
            fulfillment_task_id: task.id,
            already_open: result[:already_open]
          }, status: result[:already_open] ? :ok : :created
        else
          render_order_refused(result[:error])
        end
      end

      sig { void }
      def received
        merchant = require_api_merchant!
        return if merchant.nil?
        return if refuse_unusable_strings(%i[bin_code], coded: false)

        bin_code = string_param(:bin_code).to_s
        if bin_code.length > WarehouseBin::MAX_CODE_LENGTH
          render(
            json: { error: "bin_code must be at most #{WarehouseBin::MAX_CODE_LENGTH} characters" },
            status: :unprocessable_content
          )
          return
        end

        form = Returns::ReturnedLinesForm.new(params[:lines])
        unless form.well_formed?
          render(
            json: { error: "lines must be a list of objects, each with a sku and a quantity" },
            status: :bad_request
          )
          return
        end

        problem = form.problem
        if problem
          render json: { error: problem }, status: :unprocessable_content
          return
        end

        relay = T.let(Container[:order_grpc_client], Order::ReturnRelay)
        result = relay.return_goods_received(
          merchant_principal_id: T.must(merchant.principal_id),
          return_number: params[:return_number].to_s,
          lines: form.lines,
          bin_code: bin_code,
          received_at: Time.current.utc
        )

        if result[:accepted]
          render json: {
            return_number: params[:return_number].to_s,
            already_recorded: result[:already_recorded]
          }, status: :ok
        else
          render_order_refused(result[:error])
        end
      end

      private

      sig { params(merchant: Merchant, task_id: T.nilable(Integer)).returns(T.nilable(FulfillmentTask)) }
      def find_task(merchant, task_id)
        repository = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
        task = task_id && repository.find_by_id(merchant_id: merchant.id, id: task_id)

        if task.nil?
          render json: { error: "Fulfillment task not found" }, status: :not_found
          return nil
        end

        task
      end

      sig { params(detail: T.nilable(String)).void }
      def render_order_refused(detail)
        render json: {
          error: "RETURN_NOT_RECORDED",
          message: detail || "order did not accept this return, so nothing was recorded"
        }, status: :bad_gateway
      end
    end
  end
end
