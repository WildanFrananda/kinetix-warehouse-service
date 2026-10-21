# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "two first receipts of one sku into one bin, at the same moment" do
  self.use_transactional_tests = false

  let(:owner) { "dddddddd-1111-4222-8333-444444444444" }
  let(:staff) { "eeeeeeee-1111-4222-8333-444444444444" }
  let!(:bin) { WarehouseBin.create!(bin_code: "RACE-01", zone: "R", shelf_level: 1) }

  before { Merchant.create!(principal_id: owner, cutoff_hour: 14) }

  after do
    StockReceipt.where(warehouse_bin_id: bin.id).delete_all
    BinInventory.where(warehouse_bin_id: bin.id).delete_all
    bin.delete
    Merchant.where(principal_id: owner).delete_all
  end

  def book(key, quantity)
    resolver = Merchants::ResolveService.new(
      merchant_repository: MerchantRepository.new,
      identity_client: FakeIdentityClient.new
    )

    Inventory::ReceiveStockService.new(
      bin_code: "RACE-01",
      sku: "SKU-RACE",
      quantity: quantity,
      idempotency_key: key,
      received_by_principal_id: staff,
      merchant_principal_id: owner,
      resolve_merchant_service: resolver
    ).call
  end

  it "books both on one inventory row, each on its own connection" do
    arrived = Queue.new
    release = Queue.new
    creating = %i[create! insert_all]

    creating.each do |name|
      allow(BinInventory).to receive(name).and_wrap_original do |original, *args, **kwargs, &block|
        arrived << Thread.current
        release.pop(timeout: 10)
        original.call(*args, **kwargs, &block)
      end
    end

    threads = [ [ "RACE-A", 5 ], [ "RACE-B", 3 ] ].map do |key, quantity|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { book(key, quantity) }
      rescue StandardError => e
        e
      end
    end

    2.times { arrived.pop(timeout: 10) }
    2.times { release << :go }
    outcomes = threads.map(&:value)

    expect(outcomes).to all(be_a(Inventory::ReceiveStockService::Result))
    expect(outcomes.map(&:error)).to eq([ nil, nil ])
    expect(BinInventory.where(warehouse_bin_id: bin.id, sku: "SKU-RACE").count).to eq(1)
    expect(BinInventory.find_by(warehouse_bin_id: bin.id, sku: "SKU-RACE").quantity).to eq(8)
    expect(StockReceipt.where(warehouse_bin_id: bin.id).count).to eq(2)
  end
end
