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
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_unreadable_body
    rescue_from Identity::Unavailable, with: :render_identity_unavailable
    rescue_from Order::Unavailable, with: :render_order_unavailable
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

  sig { params(exception: Identity::Unavailable).void }
  def render_identity_unavailable(exception)
    Rails.logger.warn(
      "identity could not be asked about #{exception.principal_id} " \
      "(request_id=#{trace_id}): #{exception.message}"
    )

    response.headers["Retry-After"] = "15"
    render json: {
      error: "IDENTITY_UNAVAILABLE",
      message: "we could not check this account with identity, so the request was not applied. " \
               "No stock was moved or reserved.",
      traceId: trace_id
    }, status: :service_unavailable
  end

  sig { params(exception: Order::Unavailable).void }
  def render_order_unavailable(exception)
    Rails.logger.warn("order could not be asked (request_id=#{trace_id}): #{exception.message}")

    response.headers["Retry-After"] = "15"
    render json: {
      error: "ORDER_UNAVAILABLE",
      message: "order-service did not answer, so nothing was recorded. Try again shortly.",
      traceId: trace_id
    }, status: :service_unavailable
  end

  sig { params(exception: ActionDispatch::Http::Parameters::ParseError).void }
  def render_unreadable_body(exception)
    Rails.logger.info("unreadable body serving #{request.path} (request_id=#{trace_id}): #{exception.message}")

    render json: {
      error: "INVALID_REQUEST",
      message: "the request body could not be parsed as the content type it declares.",
      traceId: trace_id
    }, status: :bad_request
  end
end
