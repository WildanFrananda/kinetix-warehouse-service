# typed: strict
# frozen_string_literal: true

module ApiErrorHandling
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ActionController::Base }

  included do
    T.bind(self, T.class_of(ActionController::Base))

    rescue_from StandardError, with: :render_internal_error
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActionController::ParameterMissing, with: :render_bad_request
  end

  private

  sig { returns(String) }
  def trace_id
    Kinetix::RequestId.current || request.request_id || "-"
  end

  sig { params(exception: StandardError).void }
  def render_internal_error(exception)
    Rails.logger.error(
      "unhandled exception serving #{request.method} #{request.path} " \
      "(request_id=#{trace_id}): #{exception.class}: #{exception.message}"
    )
    Rails.logger.error(exception.backtrace&.first(20)&.join("\n").to_s)

    render json: {
      error: "INTERNAL_ERROR",
      message: "something went wrong handling this request. No stock was moved or reserved " \
               "unless a previous response said so.",
      traceId: trace_id
    }, status: :internal_server_error
  end

  sig { params(exception: ActiveRecord::RecordNotFound).void }
  def render_not_found(exception)
    Rails.logger.info("not found serving #{request.path} (request_id=#{trace_id}): #{exception.message}")

    render json: {
      error: "NOT_FOUND",
      message: "no record of this service matches that request.",
      traceId: trace_id
    }, status: :not_found
  end

  sig { params(exception: ActionController::ParameterMissing).void }
  def render_bad_request(exception)
    render json: {
      error: "INVALID_REQUEST",
      message: "the request is missing #{exception.param}.",
      traceId: trace_id
    }, status: :bad_request
  end
end
