# typed: strict

class BaseService
  extend T::Sig

  NOT_FOUND = "NOT_FOUND"

  class Result < T::Struct
    extend T::Sig

    const :success, T::Boolean
    const :data, T.nilable(T.anything)
    const :error, T.nilable(String)
    const :error_code, T.nilable(String), default: nil

    sig { returns(T::Boolean) }
    def success?
      success
    end

    sig { returns(T::Boolean) }
    def failure?
      !success
    end

    sig { returns(T::Boolean) }
    def not_found?
      error_code == NOT_FOUND
    end
  end

  protected

  sig { params(data: T.anything).returns(Result) }
  def success(data)
    Result.new(success: true, data: data, error: nil)
  end

  sig { params(error: String).returns(Result) }
  def failure(error)
    Result.new(success: false, data: nil, error: error)
  end

  sig { params(error: String).returns(Result) }
  def not_found(error)
    Result.new(success: false, data: nil, error: error, error_code: NOT_FOUND)
  end
end
