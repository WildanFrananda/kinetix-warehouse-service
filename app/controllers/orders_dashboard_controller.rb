# typed: strict

class OrdersDashboardController < ApplicationController
  extend T::Sig

  class OrderCardItemData < T::Struct
    const :sku, String
    const :product_name, String
    const :quantity, Integer
    const :price, BigDecimal
    const :bin_location, String
  end


  class OrderCardData < T::Struct
    const :id, Integer
    const :order_number, String
    const :buyer_name, String
    const :shipping_address, String
    const :status, String
    const :sla_urgency, String
    const :created_at, T.nilable(Time)
    const :items, T::Array[OrderCardItemData]
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


    service = T.let(Container[:get_order_queue_service], Orders::GetOrderQueueService)
    result = service.call(merchant_id: merchant_id)

    order_cards = T.cast(result.success? ? result.data : [], T::Array[OrdersDashboardController::OrderCardData])
    render Views::OrdersDashboard::Index.new(

      order_cards: order_cards,
      current_merchant: @current_merchant,
      merchants: @merchants,
      status_filter: params[:status_filter].to_s,
      notice_flash: flash[:notice],
      alert_flash: flash[:alert]
    ), layout: false
  end


  sig { void }
  def print_label
    order_id = params[:id].to_i
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1

    service = T.let(Container[:generate_shipping_label_service], Labels::GenerateShippingLabelService)
    result = service.call(merchant_id: merchant_id, order_id: order_id)

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
    order_id = params[:id].to_i
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1

    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    @merchant = T.let(merchant_repo.find_by_id(merchant_id), T.nilable(Merchant))

    order_repo = T.let(Container[:order_repository], OrderRepositoryInterface)
    @order = T.let(order_repo.find_by_id(merchant_id: merchant_id, id: order_id), T.nilable(Order))

    service = T.let(Container[:generate_shipping_label_service], Labels::GenerateShippingLabelService)
    result = service.call(merchant_id: merchant_id, order_id: order_id)

    @label = T.let(result.success? ? T.cast(result.data, Labels::GenerateShippingLabelService::ResultData) : nil, T.nilable(Labels::GenerateShippingLabelService::ResultData))
    render layout: false
  end

  sig { void }
  def dispatch_fleet_pulse
    order_id = params[:id].to_i
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1

    service = T.let(Container[:dispatch_fleet_pulse_service], Couriers::DispatchFleetPulseService)
    result = service.call(merchant_id: merchant_id, order_id: order_id)

    if result.success?
      update_service = T.let(Container[:update_order_status_service], Orders::UpdateOrderStatusService)
      update_service.call(merchant_id: merchant_id, order_id: order_id, new_status: "dispatched")

      dispatch_data = T.cast(result.data, Couriers::DispatchFleetPulseService::ResultData)
      flash[:notice] = "🛵 Courier Dispatch Requested to FleetPulse! Dispatch Ref: #{dispatch_data.dispatch_ref}"
    else
      flash[:alert] = "⚠️ Failed to dispatch to FleetPulse: #{result.error}"
    end

    redirect_to orders_path(merchant_id: merchant_id)
  end

  sig { void }
  def update_status
    order_id = params[:id].to_i
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1
    new_status = params[:status].to_s

    service = T.let(Container[:update_order_status_service], Orders::UpdateOrderStatusService)
    result = service.call(merchant_id: merchant_id, order_id: order_id, new_status: new_status)

    if result.success?
      flash[:notice] = "📦 Order ##{order_id} status updated to '#{new_status.tr('_', ' ').capitalize}'!"
    else
      flash[:alert] = "⚠️ Failed to update order status: #{result.error}"
    end

    redirect_to orders_path(merchant_id: merchant_id)
  end

  sig { void }
  def create_manual_order
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1
    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchant = merchant_repo.find_by_id(merchant_id)
    merchant_code = merchant ? merchant.code : "BH"


    buyer_name = params[:buyer_name].to_s.strip
    buyer_phone = params[:buyer_phone].to_s.strip
    shipping_address = params[:shipping_address].to_s.strip
    product_name = params[:product_name].to_s.strip
    sku = params[:sku].to_s.strip
    price = params[:price].present? ? BigDecimal(params[:price].to_s) : BigDecimal("150000")

    item_input = Orders::CreateOrderForm::ItemInput.new(
      sku: sku,
      product_name: product_name,
      quantity: 1,
      price: price
    )

    generated_ord_num = "ORD-#{merchant_code}-#{Time.current.to_i.to_s.last(4)}"


    form = Orders::CreateOrderForm.new(
      order_number: generated_ord_num,
      buyer_name: buyer_name,
      buyer_phone: buyer_phone,
      shipping_address: shipping_address,
      total_amount: price,
      items: [ item_input ]
    )

    service = T.let(Container[:create_order_service], Orders::CreateOrderService)
    result = service.call(merchant_id: merchant_id, form: form)

    if result.success?
      order_data = T.cast(result.data, Orders::CreateOrderService::ResultData)
      flash[:notice] = "✨ New Manual Order ##{order_data.order_number} successfully created!"
    else
      flash[:alert] = "⚠️ Failed to create manual order: #{result.error}"
    end

    redirect_to orders_path(merchant_id: merchant_id)
  end

  sig { void }
  def emergency_halt
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1

    flash[:alert] = "🚨 WAREHOUSE EMERGENCY HALT ACTIVATED! All automated courier dispatches & picking processes temporarily paused."
    redirect_to orders_path(merchant_id: merchant_id)
  end
end
