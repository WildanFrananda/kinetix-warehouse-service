# typed: strict

module Api
  module V1
    class BinsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStaffAuthorization

      sig { void }
      def create
        return unless require_staff!

        bin = WarehouseBin.find_or_initialize_by(bin_code: params[:bin_code].to_s)
        existed = bin.persisted?
        bin.zone = params[:zone].to_s if params[:zone].present?
        bin.shelf_level = params[:shelf_level].to_i if params[:shelf_level].present?

        if bin.save
          render json: {
            id: bin.id, bin_code: bin.bin_code, zone: bin.zone, shelf_level: bin.shelf_level
          }, status: existed ? :ok : :created
        else
          render json: { error: bin.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end
    end
  end
end
