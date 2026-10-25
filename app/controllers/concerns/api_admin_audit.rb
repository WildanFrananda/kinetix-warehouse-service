# typed: strict
# frozen_string_literal: true

module ApiAdminAudit
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ActionController::Base }
  requires_ancestor { ApiAuthentication }

  EVENT = "admin_action"
  UNREAD = "-"
  MAX_TARGET_LENGTH = 200

  private

  sig { params(action: String, target_keys: T::Array[Symbol], blk: T.proc.void).void }
  def audit_admin_action(action, target_keys:, &blk)
    begin
      yield
    rescue StandardError => e
      raise unless rescue_with_handler(e)
    end

    outcome = Kinetix::Metrics::AdminActions.outcome_for(response.status)
    Kinetix::Metrics::AdminActions.record(action: action, outcome: outcome)
    Rails.logger.info(
      "#{EVENT} actor=#{api_claims.principal_id} action=#{action} " \
      "target=#{JSON.generate(admin_target(target_keys))} outcome=#{outcome} " \
      "request_id=#{Kinetix::RequestId.current || request.request_id || UNREAD}"
    )
  end

  sig { params(keys: T::Array[Symbol]).returns(String) }
  def admin_target(keys)
    keys.map { |key| target_part(params[key]) }.join("/")[0, MAX_TARGET_LENGTH].to_s
  rescue ActionDispatch::Http::Parameters::ParseError
    UNREAD
  end

  sig { params(value: T.untyped).returns(String) }
  def target_part(value)
    return value if value.is_a?(String) && !value.empty?
    return value.to_s if value.is_a?(Integer)

    UNREAD
  end
end
