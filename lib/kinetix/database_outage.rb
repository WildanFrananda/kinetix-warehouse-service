# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "pg"
require "active_record"

module Kinetix
  module DatabaseOutage
    extend T::Sig

    UNREACHABLE = T.let(
      [ ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed ].freeze,
      T::Array[T.class_of(StandardError)]
    )

    NOT_SERVING = T.let(
      [
        PG::ConnectionBad,
        PG::UnableToSend,
        PG::ConnectionException,
        PG::AdminShutdown,
        PG::CrashShutdown,
        PG::CannotConnectNow,
        PG::TooManyConnections
      ].freeze,
      T::Array[T.class_of(StandardError)]
    )

    sig { params(error: Exception).returns(T::Boolean) }
    def self.explains?(error)
      return false if error.is_a?(ActiveRecord::ConnectionNotDefined)
      return true if UNREACHABLE.any? { |kind| error.is_a?(kind) }
      return false unless error.is_a?(ActiveRecord::StatementInvalid)

      cause = error.cause
      NOT_SERVING.any? { |kind| cause.is_a?(kind) }
    end
  end
end
