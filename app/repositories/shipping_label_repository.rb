# typed: strict

class ShippingLabelRepository < BaseRepository
  include ShippingLabelRepositoryInterface
  extend T::Sig

  sig { void }
  def initialize
    super(ShippingLabel)
  end

  sig { override.params(label_id: Integer).returns(ShippingLabel) }
  def record_print(label_id:)
    model.where(id: label_id).update_all(
      [ "print_count = print_count + 1, reprint_count = print_count, updated_at = ?", Time.current ]
    )

    T.cast(model.find(label_id), ShippingLabel)
  end
end
