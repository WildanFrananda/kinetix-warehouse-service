# typed: strict
# frozen_string_literal: true

module ApiStaffAuthorization
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ActionController::Base }
  requires_ancestor { ApiAuthentication }

  private

  sig { returns(T::Boolean) }
  def require_staff!
    if api_claims.role != "admin"
      render json: { error: "Forbidden: this account may not perform warehouse operations" },
             status: :forbidden
      return false
    end

    true
  end
end
