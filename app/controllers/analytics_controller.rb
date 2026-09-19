# typed: strict

class AnalyticsController < ApplicationController
  extend T::Sig

  class TopSkuData < T::Struct
    const :sku, String
    const :total_units_picked, Integer
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

    task_repo = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    all_merchant_tasks = task_repo.due_today(merchant_id: merchant_id)

    total_orders_count = all_merchant_tasks.size
    overdue_count = 0
    on_time_count = 0

    now = Time.current

    all_merchant_tasks.each do |ord|
      cutoff = ord.same_day_cutoff_at
      if cutoff && cutoff < now && [ "received", "packing" ].include?(ord.status)
        overdue_count += 1
      else
        on_time_count += 1
      end
    end

    sla_rate_pct = total_orders_count.positive? ? ((on_time_count.to_f / total_orders_count) * 100).round(1).to_f : 100.0

    @total_orders = T.let(total_orders_count, T.nilable(Integer))
    @sla_compliance_rate = T.let(sla_rate_pct, T.nilable(Float))
    @overdue_orders_count = T.let(overdue_count, T.nilable(Integer))

    lines = FulfillmentTaskLine.joins(:fulfillment_task)
                               .where(fulfillment_tasks: { merchant_id: merchant_id }).to_a
    top_map = T.let({}, T::Hash[String, TopSkuData])

    lines.each do |line|
      sku = line.sku.to_s
      next if sku.empty?

      qty = line.quantity || 1
      existing = top_map[sku]
      top_map[sku] = TopSkuData.new(
        sku: sku,
        total_units_picked: (existing ? existing.total_units_picked : 0) + qty
      )
    end

    sorted_skus = top_map.values.sort_by { |p| -p.total_units_picked }
    render Views::Analytics::Index.new(
      sla_compliance_rate: sla_rate_pct,
      total_orders: total_orders_count,
      overdue_orders_count: overdue_count,
      top_skus: sorted_skus,
      current_merchant: @current_merchant,
      merchants: @merchants
    ), layout: false
  end
end
