# typed: strict
# frozen_string_literal: true

require_relative "request_id"

module Kinetix
  class RequestIdMiddleware
    extend T::Sig

    sig { params(app: T.untyped).void }
    def initialize(app)
      @app = app
    end

    sig { params(env: T::Hash[String, T.untyped]).returns(T.untyped) }
    def call(env)
      Kinetix::RequestId.with(env["action_dispatch.request_id"]) do
        @app.call(env)
      end
    end
  end
end
