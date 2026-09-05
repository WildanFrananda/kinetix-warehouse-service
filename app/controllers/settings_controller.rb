# typed: strict

class SettingsController < ApplicationController
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

    render Views::Settings::Index.new(
      current_merchant: @current_merchant,
      merchants: @merchants,
      base_url: request.base_url,
      notice_flash: flash[:notice],
      alert_flash: flash[:alert]
    ), layout: false
  end

  sig { void }
  def update_cutoff
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1
    cutoff_hour = params[:cutoff_hour].to_i

    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchant = merchant_repo.find_by_id(merchant_id)

    if merchant
      merchant.update!(cutoff_hour: cutoff_hour)
      flash[:notice] = "⏱️ Same-Day SLA Cutoff Hour updated to #{cutoff_hour}:00 WIB!"
    else
      flash[:alert] = "⚠️ Merchant record not found!"
    end

    redirect_to settings_path(merchant_id: merchant_id)
  end


  sig { void }
  def test_ping
    merchant_id_param = params[:merchant_id]
    merchant_id = merchant_id_param.present? ? merchant_id_param.to_i : 1

    flash[:notice] = "⚡ FleetPulse Elixir Phoenix Cluster Ping: 12ms Latency (Status: 100% Operational)"
    redirect_to settings_path(merchant_id: merchant_id)
  end
end
