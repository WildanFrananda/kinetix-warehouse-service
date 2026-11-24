# typed: strict

module Api
  module V1
    class MerchantsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling

      sig { void }
      def me
        standing = require_api_standing!
        return if standing.nil?

        setting = standing.setting
        render json: {
          id: setting.id,
          principal_id: setting.merchant_principal_id,
          cutoff_hour: setting.cutoff_hour,
          may_sell: standing.may_sell
        }, status: :ok
      end

      sig { void }
      def update
        setting = require_trading_merchant!
        return if setting.nil?

        id = Kinetix::IntegerParam.id(params[:id])
        if id.nil?
          render json: { error: "Merchant not found" }, status: :not_found
          return
        end

        if setting.id != id
          render json: { error: "Forbidden: that merchant is not yours" }, status: :forbidden
          return
        end

        raw = params[:cutoff_hour]
        if raw.blank?
          render json: { error: "cutoff_hour is required" }, status: :unprocessable_content
          return
        end

        unless raw.to_s.match?(/\A[0-9]{1,2}\z/)
          render json: { error: "cutoff_hour must be a whole number of hours" }, status: :unprocessable_content
          return
        end

        cutoff_hour = raw.to_i
        unless (0..23).cover?(cutoff_hour)
          render json: { error: "cutoff_hour must be between 0 and 23" }, status: :unprocessable_content
          return
        end

        setting.update!(cutoff_hour: cutoff_hour)
        render json: { id: setting.id, cutoff_hour: setting.cutoff_hour }, status: :ok
      end
    end
  end
end
