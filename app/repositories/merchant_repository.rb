# typed: strict
# frozen_string_literal: true

class MerchantRepository < BaseRepository
  include MerchantRepositoryInterface

  sig { params(model: T.class_of(ActiveRecord::Base)).void }
  def initialize(model = Merchant)
    super(model)
  end

  sig { override.params(id: Integer).returns(T.nilable(Merchant)) }
  def find_by_id(id)
    T.cast(model.find_by(id: id), T.nilable(Merchant))
  end

  sig { override.params(principal_id: String).returns(T.nilable(Merchant)) }
  def find_by_principal_id(principal_id)
    canonical = Kinetix::PrincipalId.canonical(principal_id)
    return nil if canonical.nil?

    T.cast(model.find_by(principal_id: canonical), T.nilable(Merchant))
  end

  sig { override.params(principal_id: String).returns(Merchant) }
  def project(principal_id)
    T.cast(model.create!(principal_id: principal_id), Merchant)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    found = find_by_principal_id(principal_id)
    raise e if found.nil?

    found
  end
end
