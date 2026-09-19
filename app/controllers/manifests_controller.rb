# typed: strict

class ManifestsController < ApplicationController
  extend T::Sig

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

    task_repo = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    orders = task_repo.due_today(merchant_id: merchant_id)

    render Views::Manifests::Index.new(
      dispatched_orders: orders,
      current_merchant: @current_merchant,
      merchants: @merchants
    ), layout: false
  end


  sig { void }
  def handover_pdf
    merchant_id_param = params[:merchant_id]
    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchants = Merchant.order(:name).to_a

    selected_merchant = if merchant_id_param.present?
      merchant_repo.find_by_id(merchant_id_param.to_i)
    else
      merchants.first
    end

    @current_merchant = T.let(selected_merchant || merchants.first, T.nilable(Merchant))
    current = @current_merchant
    merchant_id = current ? current.id : 1

    task_repo = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    orders = task_repo.due_today(merchant_id: merchant_id)

    @dispatched_orders = T.let(orders, T.nilable(T::Array[Order]))
    render layout: false
  end
end
