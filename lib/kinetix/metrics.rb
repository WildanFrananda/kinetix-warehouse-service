# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "metrics/collection"

module Kinetix
  module Metrics
    extend T::Sig

    @collection = T.let(nil, T.nilable(Collection))
    @collection_mutex = T.let(Mutex.new, Mutex)

    sig { returns(Collection) }
    def self.collection
      @collection_mutex.synchronize { @collection ||= Collection.new }
    end
  end
end

require_relative "metrics/grpc_client_recorder"
require_relative "metrics/grpc_server_interceptor"
require_relative "metrics/http_middleware"
require_relative "metrics/http_server"
require_relative "metrics/route_template"
