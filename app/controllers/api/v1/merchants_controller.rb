# typed: strict

module Api
  module V1
    class MerchantsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling

      sig { void }
      def update
        merchant = require_api_merchant!
        return if merchant.nil?

        if merchant.id != params[:id].to_i
          render json: { error: "Forbidden: that merchant is not yours" }, status: :forbidden
          return
        end

        raw = params[:cutoff_hour]
        if raw.blank?
          render json: { error: "cutoff_hour is required" }, status: :unprocessable_entity
          return
        end

        unless raw.to_s.match?(/\A[0-9]{1,2}\z/)
          render json: { error: "cutoff_hour must be a whole number of hours" },
                 status: :unprocessable_entity
          return
        end

        cutoff_hour = raw.to_i
        unless (0..23).cover?(cutoff_hour)
          render json: { error: "cutoff_hour must be between 0 and 23" }, status: :unprocessable_entity
          return
        end

        merchant.update!(cutoff_hour: cutoff_hour)
        render json: { id: merchant.id, cutoff_hour: merchant.cutoff_hour }, status: :ok
      end
    end
  end
end
