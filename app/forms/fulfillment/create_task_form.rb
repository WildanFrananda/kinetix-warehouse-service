# typed: strict

module Fulfillment
  class CreateTaskForm
    extend T::Sig

    class LineInput < T::Struct
      const :sku, String
      const :quantity, Integer
    end

    sig { returns(String) }
    attr_reader :order_number

    sig { returns(T::Array[LineInput]) }
    attr_reader :lines

    sig { returns(T::Array[String]) }
    attr_reader :errors

    sig { params(order_number: String, lines: T::Array[LineInput]).void }
    def initialize(order_number:, lines:)
      @order_number = order_number
      @lines = lines
      @errors = T.let([], T::Array[String])
    end

    sig { returns(T::Boolean) }
    def valid?
      @errors.clear
      @errors << "Order number cannot be blank" if @order_number.strip.empty?
      @errors << "A task with no lines is nothing to pick" if @lines.empty?
      @errors << "Every line needs a SKU" if @lines.any? { |line| line.sku.strip.empty? }
      @errors << "Every line needs a quantity greater than zero" if @lines.any? { |line| line.quantity <= 0 }
      @errors.empty?
    end
  end
end
