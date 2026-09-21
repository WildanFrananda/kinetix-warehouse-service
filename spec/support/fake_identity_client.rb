# typed: false
# frozen_string_literal: true

class FakeIdentityClient
  include IdentityMerchantLookupInterface

  attr_reader :asked

  def initialize(may_sell: true, known: true, unavailable: false, merchant_principal_id: nil,
                 status: "MERCHANT_STATUS_VERIFIED")
    @may_sell = may_sell
    @known = known
    @unavailable = unavailable
    @merchant_principal_id = merchant_principal_id
    @status = status
    @asked = []
  end

  def merchant_info(principal_id)
    @asked << principal_id
    raise Identity::Unavailable.new(principal_id, "stubbed outage") if @unavailable
    return nil unless @known

    {
      may_sell: @may_sell,
      merchant_principal_id: @merchant_principal_id || principal_id,
      store_name: "Fake Store",
      status: @status
    }
  end
end

RSpec.shared_context "identity answers about merchants" do
  let(:identity_client) { FakeIdentityClient.new }

  before do
    resolver = Merchants::ResolveService.new(
      merchant_repository: Container[:merchant_repository],
      identity_client: identity_client
    )

    allow(Container).to receive(:[]).and_call_original
    allow(Container).to receive(:[]).with(:resolve_merchant_service).and_return(resolver)
  end
end
