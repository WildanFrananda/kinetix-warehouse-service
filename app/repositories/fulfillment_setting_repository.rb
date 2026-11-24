# typed: strict
# frozen_string_literal: true

class FulfillmentSettingRepository < BaseRepository
  include FulfillmentSettingRepositoryInterface

  sig { params(model: T.class_of(ActiveRecord::Base)).void }
  def initialize(model = FulfillmentSetting)
    super(model)
  end

  sig { override.params(id: Integer).returns(T.nilable(FulfillmentSetting)) }
  def find_by_id(id)
    T.cast(model.find_by(id: id), T.nilable(FulfillmentSetting))
  end

  sig { override.params(principal_id: String).returns(T.nilable(FulfillmentSetting)) }
  def find_by_principal_id(principal_id)
    canonical = Kinetix::PrincipalId.canonical(principal_id)
    return nil if canonical.nil?

    T.cast(model.find_by(merchant_principal_id: canonical), T.nilable(FulfillmentSetting))
  end

  sig { override.params(principal_id: String).returns(FulfillmentSetting) }
  def project(principal_id)
    canonical = Kinetix::PrincipalId.canonical(principal_id) || principal_id
    T.cast(model.create!(merchant_principal_id: canonical), FulfillmentSetting)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    found = find_by_principal_id(principal_id)
    raise e if found.nil?

    found
  end
end
