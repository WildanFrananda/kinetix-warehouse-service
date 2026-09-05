# Hand-written shims for the generated gRPC stubs.
#
# `creds` was typed `Symbol` because the only value ever passed was
# `:this_channel_is_insecure`. Every client speaks mTLS now and passes a
# `GRPC::Core::ChannelCredentials`, which the real `Stub#initialize` has always accepted — the
# shim was narrower than the thing it describes, so widening it is a correction, not a
# concession.
# typed: true

module Google
  module Protobuf
    class DescriptorPool
      extend T::Sig
      sig { returns(DescriptorPool) }
      def self.generated_pool; end

      sig { params(name: String).returns(T.untyped) }
      def lookup(name); end
    end

    class RepeatedField
      include Enumerable
      extend T::Sig
      sig { params(args: T.untyped).void }
      def initialize(*args); end
    end
  end
end

# The message and service classes are NOT declared here any more.
#
# They used to be, field by field, and the hand-written copy described `merchant_api_key` and a
# `CheckBinStockResponse` with no `found` — the shape before the contract. Once the real types
# came from the kinetix-contracts gem, this file was a second, older description of the same
# classes, and Sorbet believed it: twenty-one errors saying fields that exist do not.
#
# `bin/tapioca gem kinetix-contracts` generates them from the gem now. What stays below is only
# what tapioca cannot see.

module GRPC
  class ActiveCall
    class SingleReqView; end
  end
end
