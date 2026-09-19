# typed: strict

class OrdersDashboardController < ApplicationController
  extend T::Sig

  class TaskCardLineData < T::Struct
    const :sku, String
    const :quantity, Integer
    const :bin_location, String
  end


  class TaskCardData < T::Struct
    const :id, Integer
    const :order_number, String
    const :status, String
    const :sla_urgency, String
    const :created_at, T.nilable(Time)
    const :lines, T::Array[TaskCardLineData]
  end


  sig { void }
  def index
    merchant_id_param = params[:merchant_id]
    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchants = Merchant.order(:name).to_a
    @merchants = T.let(merchants, T.nilable(T::Array[Merchant]))

    merchant_id = active_merchant_id
    selected_merchant = merchant_repo.find_by_id(merchant_id)

    @current_merchant = T.let(selected_merchant || merchants.first, T.nilable(Merchant))
    current = @current_merchant
    merchant_id = current ? current.id : 1


    service = T.let(Container[:task_queue_service], Fulfillment::TaskQueueService)
    result = service.call(merchant_id: merchant_id)

    task_cards = T.cast(result.success? ? result.data : [], T::Array[Fulfillment::TaskQueueService::TaskCardData])
    render Views::OrdersDashboard::Index.new(

      task_cards: task_cards,
      current_merchant: @current_merchant,
      merchants: @merchants,
      status_filter: params[:status_filter].to_s,
      notice_flash: flash[:notice],
      alert_flash: flash[:alert]
    ), layout: false
  end


  sig { void }
  def print_label
    task_id = params[:id].to_i
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1

    service = T.let(Container[:generate_shipping_label_service], Labels::GenerateShippingLabelService)
    result = service.call(merchant_id: merchant_id, fulfillment_task_id: task_id)

    if result.success?
      label_data = T.cast(result.data, Labels::GenerateShippingLabelService::ResultData)
      flash[:notice] = "🎉 Resi AWB Successfully Generated! AWB Number: #{label_data.awb_number} (Reprint Count: #{label_data.reprint_count})"
    else
      flash[:alert] = "⚠️ Failed to generate label: #{result.error}"
    end

    redirect_to orders_path(merchant_id: merchant_id)
  end

  sig { void }
  def label_view
    task_id = params[:id].to_i
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1

    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    @merchant = T.let(merchant_repo.find_by_id(merchant_id), T.nilable(Merchant))

    task_repo = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    @task = T.let(task_repo.find_by_id(merchant_id: merchant_id, id: task_id), T.nilable(FulfillmentTask))

    service = T.let(Container[:generate_shipping_label_service], Labels::GenerateShippingLabelService)
    result = service.call(merchant_id: merchant_id, fulfillment_task_id: task_id)

    @label = T.let(result.success? ? T.cast(result.data, Labels::GenerateShippingLabelService::ResultData) : nil, T.nilable(Labels::GenerateShippingLabelService::ResultData))
    render layout: false
  end

  sig { void }
  def update_status
    task_id = params[:id].to_i
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1
    new_status = params[:status].to_s

    service = T.let(Container[:advance_task_service], Fulfillment::AdvanceTaskService)
    result = service.call(merchant_id: merchant_id, task_id: task_id, new_status: new_status)

    if result.success?
      flash[:notice] = "📦 Task ##{task_id} status updated to '#{new_status.tr('_', ' ').capitalize}'!"
    else
      flash[:alert] = "⚠️ Failed to update order status: #{result.error}"
    end

    redirect_to orders_path(merchant_id: merchant_id)
  end
end
