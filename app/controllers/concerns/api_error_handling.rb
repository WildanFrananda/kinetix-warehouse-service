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
    rescue_from Order::TimedOut, with: :render_order_timed_out
    rescue_from Order::CallFailed, with: :render_order_failed
  end

  RETRY_AFTER_SECONDS = "15"

  private

  sig { returns(String) }
  def trace_id
    Kinetix::RequestId.current || request.request_id || "-"
  end

  sig { params(exception: StandardError).void }
  def render_internal_error(exception)
    return render_database_unavailable(exception) if Kinetix::DatabaseOutage.explains?(exception)

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

  sig { params(exception: StandardError).void }
  def render_database_unavailable(exception)
    Rails.logger.error(
      "the database could not be reached serving #{request.method} #{request.path} " \
      "(request_id=#{trace_id}): #{exception.class}: #{exception.message}"
    )

    response.headers["Retry-After"] = RETRY_AFTER_SECONDS
    render json: {
      error: "DATABASE_UNAVAILABLE",
      message: "warehouse could not reach its database, so this request could not be completed. Try again shortly.",
      traceId: trace_id
    }, status: :service_unavailable
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

    response.headers["Retry-After"] = RETRY_AFTER_SECONDS
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

    response.headers["Retry-After"] = RETRY_AFTER_SECONDS
    render json: {
      error: "ORDER_UNAVAILABLE",
      message: "order-service could not take this request, so nothing was recorded. Try again shortly.",
      traceId: trace_id
    }, status: :service_unavailable
  end

  sig { params(exception: Order::TimedOut).void }
  def render_order_timed_out(exception)
    Rails.logger.warn("order did not answer in time (request_id=#{trace_id}): #{exception.message}")

    response.headers["Retry-After"] = RETRY_AFTER_SECONDS
    render json: {
      error: "ORDER_TIMEOUT",
      message: "order-service did not answer in time, so whether it recorded this is not known. Send the same " \
               "request again to find out: order records a return and its goods once, and answers already_open " \
               "or already_recorded.",
      traceId: trace_id
    }, status: :service_unavailable
  end

  sig { params(exception: Order::CallFailed).void }
  def render_order_failed(exception)
    Rails.logger.warn("order answered with an error (request_id=#{trace_id}): #{exception.message}")

    status, error, message = order_failure_answer(exception.failure)
    render json: { error: error, message: message, traceId: trace_id }, status: status
  end

  sig { params(failure: Order::Failure).returns([ Symbol, String, String ]) }
  def order_failure_answer(failure)
    case failure
    when Order::Failure::NotFound
      [ :not_found, "ORDER_NOT_FOUND", "order has no record of what this request names, so nothing was recorded." ]
    when Order::Failure::InvalidRequest
      [
        :unprocessable_content,
        "ORDER_INVALID_REQUEST",
        "order refused a value in this request, so nothing was recorded. Sending it again unchanged will not help."
      ]
    when Order::Failure::Conflict
      [
        :conflict,
        "ORDER_CONFLICT",
        "order refused this request because of the state its records are in, so nothing was recorded."
      ]
    when Order::Failure::Failed
      [
        :bad_gateway,
        "ORDER_FAILED",
        "order-service failed while handling this request, so whether it recorded anything is not known. " \
        "Sending the same request again is safe."
      ]
    else
      T.absurd(failure)
    end
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
