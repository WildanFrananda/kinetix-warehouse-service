# typed: strict
# frozen_string_literal: true

module ApiStringParams
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ActionController::Base }

  NUL = "\u0000"

  private

  sig { params(names: T::Array[Symbol], coded: T::Boolean).returns(T::Boolean) }
  def refuse_unusable_strings(names, coded:)
    names.each do |name|
      problem = string_problem(params[name])
      next if problem.nil?

      message = "#{name} #{problem}"
      body = coded ? { error: "INVALID_#{name.upcase}", message: message } : { error: message }
      render(json: body, status: :unprocessable_content)
      return true
    end

    false
  end

  sig { params(name: Symbol).returns(T.nilable(String)) }
  def string_param(name)
    value = params[name]
    return nil unless value.is_a?(String)

    value
  end

  sig { params(value: T.untyped).returns(T.nilable(String)) }
  def string_problem(value)
    return nil if value.nil?
    return "must be a string" unless value.is_a?(String)
    return "must not contain a NUL character" if value.include?(NUL)

    nil
  end
end
