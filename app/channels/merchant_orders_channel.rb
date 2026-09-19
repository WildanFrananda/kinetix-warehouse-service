# typed: strict

class MerchantOrdersChannel < ApplicationCable::Channel
  extend T::Sig

  sig { void }
  def subscribed
    merchant_id_param = params[:merchant_id]
    reject unless merchant_id_param.is_a?(Integer) || merchant_id_param.is_a?(String)

    merchant_id = merchant_id_param.to_i
    stream_from "merchant:fulfillment_tasks:#{merchant_id}"
  end
end
