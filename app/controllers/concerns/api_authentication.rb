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
    rescue Kinetix::TokenVerifier::KeysUnavailable => e
      Rails.logger.warn("identity's signing keys could not be fetched: #{e.message}")
      response.headers["Retry-After"] = "15"
      render json: {
        error: "IDENTITY_UNAVAILABLE",
        message: "we could not check this token with identity's keys, so the request was not applied."
      }, status: :service_unavailable
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
  def require_api_merchant!
    standing = require_api_standing!
    return nil if standing.nil?

    standing.merchant
  end

  sig { returns(T.nilable(Merchant)) }
  def require_trading_merchant!
    standing = require_api_standing!
    return nil if standing.nil?
    return standing.merchant if standing.may_sell

    render json: {
      error: "MERCHANT_NOT_TRADING",
      message: "identity does not permit this merchant to trade, so how its store runs cannot change."
    }, status: :forbidden
    nil
  end

  sig { returns(T.nilable(Merchants::Standing)) }
  def require_api_standing!
    unless api_claims.seller?
      render json: {
        error: "NOT_A_SELLER",
        message: "this token was not issued to a seller. An account approved as a seller after it signed in " \
                 "gets a seller's token when its session is refreshed."
      }, status: :forbidden
      return nil
    end

    service = T.let(Container[:resolve_merchant_service], Merchants::ResolveService)
    standing = service.call(principal_id: api_claims.principal_id)
    return standing if standing

    render json: {
      error: "NOT_A_MERCHANT",
      message: "identity knows no merchant for this account."
    }, status: :forbidden
    nil
  end
end
