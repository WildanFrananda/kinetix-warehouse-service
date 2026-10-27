# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "google/protobuf"

module Kinetix
  module ProtoNul
    extend T::Sig

    NUL = "\u0000"

    sig { params(message: T.untyped, prefix: String).returns(T.nilable(String)) }
    def self.field(message, prefix = "")
      message.class.descriptor.each do |descriptor|
        path = "#{prefix}#{descriptor.name}"
        found = in_value(message[descriptor.name], path)
        return found if found
      end

      nil
    end

    sig { params(value: T.untyped, path: String).returns(T.nilable(String)) }
    def self.in_value(value, path)
      case value
      when String
        value.encoding == Encoding::UTF_8 && value.include?(NUL) ? path : nil
      when Google::Protobuf::RepeatedField
        value.each do |item|
          found = in_value(item, path)
          return found if found
        end
        nil
      when Google::Protobuf::Map
        value.each do |key, item|
          found = in_value(key, path) || in_value(item, path)
          return found if found
        end
        nil
      when nil
        nil
      else
        value.class.respond_to?(:descriptor) ? field(value, "#{path}.") : nil
      end
    end
    private_class_method :in_value
  end
end
