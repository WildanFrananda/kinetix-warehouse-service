# typed: true

# The grpc gem's health-protocol classes, which its RBI does not carry.
#
# `grpc/health/v1/health_services_pb.rb` is protoc output shipped inside the gem, and tapioca
# does not pick it up, so `Grpc::Health::V1::Health::Service` — the class app/rpc/health_handler.rb
# subclasses — is invisible to Sorbet. Without this shim `srb tc` reports "Unable to resolve
# constant Health" three times and then claims `Rpc::HealthHandler.new` does not exist, which
# reads like a bug in our code rather than a missing stub.
module Grpc
  module Health
    module V1
      class HealthCheckRequest
        extend T::Sig

        sig { params(service: String).void }
        def initialize(service: ""); end

        sig { returns(String) }
        def service; end
      end

      class HealthCheckResponse
        extend T::Sig

        sig { params(status: T.untyped).void }
        def initialize(status: nil); end

        sig { returns(T.untyped) }
        def status; end
      end

      module Health
        class Service
          extend T::Sig

          sig { void }
          def initialize; end
        end

        class Stub
          extend T::Sig

          sig { params(host: String, creds: T.untyped, kw: T.untyped).void }
          def initialize(host, creds, **kw); end

          sig { params(request: T.untyped).returns(T.untyped) }
          def check(request); end
        end
      end
    end
  end
end
