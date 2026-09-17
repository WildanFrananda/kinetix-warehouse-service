# typed: strict

module Api
  module V1
    class MerchantsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling

      sig { void }
      def create
        role = api_claims.role
        unless role == "seller" || role == "admin"
          render json: { error: "Forbidden: only a seller may register a merchant here" },
                 status: :forbidden
          return
        end

        principal = api_claims.principal_id
        existing = Merchant.find_by(principal_id: principal)
        if existing
          render json: { id: existing.id, code: existing.code, name: existing.name, replayed: true },
                 status: :ok
          return
        end

        merchant = Merchant.new(
          principal_id: principal,
          name: params[:name].to_s,
          code: params[:code].to_s
        )
        merchant.latitude = params[:latitude] if params[:latitude].present?
        merchant.longitude = params[:longitude] if params[:longitude].present?

        if merchant.save
          render json: { id: merchant.id, code: merchant.code, name: merchant.name, replayed: false },
                 status: :created
        else
          render json: { error: merchant.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end
    end
  end
end
