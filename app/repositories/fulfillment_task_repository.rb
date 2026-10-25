# typed: strict

class FulfillmentTaskRepository < BaseRepository
  include FulfillmentTaskRepositoryInterface
  extend T::Sig

  TO_PACK = T.let(%w[received packing].freeze, T::Array[String])
  PACKED = "packed"

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

  sig do
    override.params(
      merchant_id: Integer,
      attributes: T::Hash[Symbol, T.anything],
      lines: T::Array[T::Hash[Symbol, T.anything]]
    ).returns(FulfillmentTask)
  end
  def create(merchant_id:, attributes:, lines:)
    model.transaction do
      task = T.cast(model.create!(attributes.merge(merchant_id: merchant_id)), FulfillmentTask)
      lines.each { |line| task.fulfillment_task_lines.create!(line) }

      task
    end
  end

  sig { override.params(merchant_id: Integer).returns(T::Array[FulfillmentTask]) }
  def open_work(merchant_id:)
    T.cast(
      model
        .left_joins(:shipping_label)
        .where(merchant_id: merchant_id)
        .where(
          "fulfillment_tasks.status IN (:to_pack) OR " \
          "(fulfillment_tasks.status = :packed AND COALESCE(shipping_labels.print_count, 0) = 0)",
          to_pack: TO_PACK,
          packed: PACKED
        )
        .includes(:fulfillment_task_lines, :shipping_label)
        .order(same_day_cutoff_at: :asc, id: :asc)
        .to_a,
      T::Array[FulfillmentTask]
    )
  end

  sig do
    override.params(
      merchant_id: Integer, task_id: Integer, status: String, from: T.nilable(String)
    ).returns(T.nilable(FulfillmentTask))
  end
  def update_status(merchant_id:, task_id:, status:, from: nil)
    return nil unless FulfillmentTask::STATUSES.include?(status)

    scope = model.where(merchant_id: merchant_id, id: task_id)
    scope = scope.where(status: from) unless from.nil?
    moved = scope.update_all(status: status, updated_at: Time.current)
    return nil if moved.zero?

    find_by_id(merchant_id: merchant_id, id: task_id)
  end

  sig { override.params(task_id: Integer, line_id: Integer).returns(T::Boolean) }
  def mark_line_scanned(task_id:, line_id:)
    now = Time.current
    marked = FulfillmentTaskLine
      .where(id: line_id, fulfillment_task_id: task_id, scanned_at: nil)
      .update_all(scanned_at: now, updated_at: now)

    marked == 1
  end

  sig { override.params(task_id: Integer).returns(Integer) }
  def lines_remaining(task_id:)
    FulfillmentTaskLine.where(fulfillment_task_id: task_id, scanned_at: nil).count
  end
end
