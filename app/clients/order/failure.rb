# typed: strict
# frozen_string_literal: true

module Order
  class Failure < T::Enum
    extend T::Sig

    enums do
      NotFound = new("not_found")
      InvalidRequest = new("invalid_request")
      Conflict = new("conflict")
      Failed = new("failed")
    end

    sig { params(code: Integer).returns(Failure) }
    def self.of(code)
      case code
      when GRPC::Core::StatusCodes::NOT_FOUND then NotFound
      when GRPC::Core::StatusCodes::INVALID_ARGUMENT then InvalidRequest
      when GRPC::Core::StatusCodes::FAILED_PRECONDITION, GRPC::Core::StatusCodes::ALREADY_EXISTS then Conflict
      else Failed
      end
    end
  end
end
