# typed: strict

module Returns
  class InitiateReturnForm
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :fulfillment_task_id

    sig { returns(String) }
    attr_reader :reason

    sig { returns(T::Array[String]) }
    attr_reader :errors

    sig { params(fulfillment_task_id: Integer, reason: String).void }
    def initialize(fulfillment_task_id:, reason:)
      @fulfillment_task_id = fulfillment_task_id
      @reason = reason
      @errors = T.let([], T::Array[String])
    end

    sig { returns(T::Boolean) }
    def valid?
      @errors.clear
      @errors << "A return must name the parcel it came back from" if @fulfillment_task_id <= 0
      @errors << "Reason cannot be blank" if @reason.strip.empty?
      @errors.empty?
    end
  end
end
