# typed: strict

module ShippingLabelRepositoryInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(label_id: Integer).returns(ShippingLabel) }
  def record_print(label_id:); end
end
