# typed: strict

class ScannerController < ApplicationController
  extend T::Sig

  class ActiveScanItemData < T::Struct
    const :id, Integer
    const :order_number, String
    const :status, String
    const :same_day_cutoff_at, T.any(Time, ActiveSupport::TimeWithZone)
    const :sku, String
    const :bin_location, String
    const :total_items_count, Integer
  end

  sig { void }
  def index
    merchant_id = active_merchant_id

    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchants = Merchant.order(:name).to_a
    @merchants = T.let(merchants, T.nilable(T::Array[Merchant]))

    selected_merchant = merchant_repo.find_by_id(merchant_id)
    @current_merchant = T.let(selected_merchant || merchants.first, T.nilable(Merchant))

    task_id_param = params[:fulfillment_task_id]
    @active_scan_target = T.let(nil, T.nilable(ActiveScanItemData))

    if task_id_param.present?
      active_task = FulfillmentTask.find_by(merchant_id: merchant_id, id: task_id_param.to_i)
      if active_task
        first_line = active_task.fulfillment_task_lines.first
        if first_line
          bin = T.cast(first_line.read_attribute(:bin_location), T.nilable(String)).presence || ""
          cutoff_val = active_task.same_day_cutoff_at || Time.current
          @active_scan_target = T.let(
            ActiveScanItemData.new(
              id: active_task.id,
              order_number: T.must(active_task.order_number),
              status: T.must(active_task.status),
              same_day_cutoff_at: cutoff_val,
              sku: T.must(first_line.sku),
              bin_location: bin,
              total_items_count: active_task.fulfillment_task_lines.count
            ),
            T.nilable(ActiveScanItemData)
          )
        end
      end
    end

    render Views::Scanner::Index.new(
      active_scan_target: @active_scan_target,
      current_merchant: @current_merchant,
      merchants: @merchants,
      notice_flash: flash[:notice],
      alert_flash: flash[:alert]
    ), layout: false
  end

  sig { void }
  def verify
    merchant_id = active_merchant_id
    task_id = params[:fulfillment_task_id].to_i
    scanned_code = params[:scanned_code].to_s

    service = T.let(Container[:verify_scan_service], Fulfillment::VerifyScanService)
    result = service.call(merchant_id: merchant_id, task_id: task_id, scanned_code: scanned_code)

    if result.success?
      res_data = T.cast(result.data, Fulfillment::VerifyScanService::ResultData)
      flash[:notice] = res_data.message
    else
      flash[:alert] = result.error
    end

    redirect_to scanner_path(merchant_id: merchant_id, fulfillment_task_id: task_id)
  end
end
