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

        result = Inventory::UpsertBinService.new(
          bin_code: params[:bin_code].to_s,
          zone: params[:zone].presence&.to_s,
          shelf_level: params[:shelf_level].present? ? params[:shelf_level].to_i : nil
        ).call

        if result.errors.any?
          render json: { error: result.errors.join(", ") }, status: :unprocessable_entity
          return
        end

        bin = result.bin
        render json: {
          id: bin.id,
          bin_code: bin.bin_code,
          zone: bin.zone,
          shelf_level: bin.shelf_level
        }, status: result.created ? :created : :ok
      end
    end
  end
end
