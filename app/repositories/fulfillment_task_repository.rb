# typed: strict

class FulfillmentTaskRepository < BaseRepository
  include FulfillmentTaskRepositoryInterface
  extend T::Sig

  sig { void }
  def initialize
    super(FulfillmentTask)
  end

  sig { override.params(merchant_id: Integer, id: Integer).returns(T.nilable(FulfillmentTask)) }
  def find_by_id(merchant_id:, id:)
    T.cast(model.find_by(merchant_id: merchant_id, id: id), T.nilable(FulfillmentTask))
  end

  sig { override.params(merchant_id: Integer, order_number: String).returns(T.nilable(FulfillmentTask)) }
  def find_by_order_number(merchant_id:, order_number:)
    T.cast(model.find_by(merchant_id: merchant_id, order_number: order_number), T.nilable(FulfillmentTask))
  end

  sig { override.params(merchant_id: Integer, attributes: T::Hash[Symbol, T.anything]).returns(FulfillmentTask) }
  def create(merchant_id:, attributes:)
    T.cast(model.create!(attributes.merge(merchant_id: merchant_id)), FulfillmentTask)
  end

  sig { override.params(merchant_id: Integer).returns(T::Array[FulfillmentTask]) }
  def due_today(merchant_id:)
    T.cast(
      model.where(merchant_id: merchant_id).order(same_day_cutoff_at: :asc).to_a,
      T::Array[FulfillmentTask]
    )
  end

  sig { override.params(merchant_id: Integer, task_id: Integer, status: String).returns(T.nilable(FulfillmentTask)) }
  def update_status(merchant_id:, task_id:, status:)
    return nil unless FulfillmentTask::STATUSES.include?(status)

    task = find_by_id(merchant_id: merchant_id, id: task_id)
    return nil unless task

    task.update!(status: status)
    task
  end
end
