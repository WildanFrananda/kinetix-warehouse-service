# typed: strict
# frozen_string_literal: true

module ApiAuthentication
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ActionController::Base }

  included do
    T.bind(self, T.class_of(ActionController::Base))

    skip_forgery_protection

    before_action :authenticate_api_caller!
  end

  private

  sig { void }
  def authenticate_api_caller!
    header = request.headers["Authorization"].to_s
    parts = header.split(" ")

    scheme = parts[0]
    token = parts[1]
    if parts.length != 2 || scheme.nil? || scheme.downcase != "bearer" || token.nil? || token.empty?
      render json: { error: "Unauthorized: a bearer token is required" }, status: :unauthorized
      return
    end

    begin
      payload = Kinetix::TokenVerifier.shared.verify_access(token)
      @api_claims = T.let(Kinetix::AccessClaims.from_payload(payload), T.nilable(Kinetix::AccessClaims))
    rescue Kinetix::TokenVerifier::InvalidToken, Kinetix::AccessClaims::Malformed
      render json: { error: "Unauthorized: invalid token" }, status: :unauthorized
      nil
    end
  end

  sig { returns(Kinetix::AccessClaims) }
  def api_claims
    claims = @api_claims
    raise "api_claims read before authentication ran" if claims.nil?

    claims
  end

  sig { returns(T.nilable(Merchant)) }
  def current_api_merchant
    role = api_claims.role
    return nil unless role == "seller" || role == "admin"

    repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    repo.find_by_principal_id(api_claims.principal_id)
  end

  sig { returns(T.nilable(Merchant)) }
  def require_api_merchant!
    merchant = current_api_merchant
    return merchant if merchant

    render json: {
      error: "Forbidden: this account is not linked to a merchant in this service"
    }, status: :forbidden
    nil
  end
end
