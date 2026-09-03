# typed: strict
# frozen_string_literal: true

class MerchantRepository < BaseRepository
  include MerchantRepositoryInterface

  sig { params(model: T.class_of(ActiveRecord::Base)).void }
  def initialize(model = Merchant)
    super(model)
    @identity_client = T.let(Identity::GrpcClient.new, Identity::GrpcClient)
  end

  sig { override.params(id: Integer).returns(T.nilable(Merchant)) }
  def find_by_id(id)
    T.cast(model.find_by(id: id), T.nilable(Merchant))
  end

  sig { override.params(api_key: String).returns(T.nilable(Merchant)) }
  def find_by_api_key(api_key)
    merchant_data = @identity_client.get_merchant_by_api_key(api_key: api_key)
    return nil unless merchant_data

    merchant = model.find_by(api_key: api_key)
    return T.cast(merchant, Merchant) if merchant

    T.cast(
      model.create!(
        name: merchant_data[:store_name],
        code: "MCH-#{Time.now.to_i}",
        api_key: api_key
      ),
      Merchant
    )
  end
end
