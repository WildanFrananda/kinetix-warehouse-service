# typed: false

require "rails_helper"

RSpec.describe "Api::V1::Bins", type: :request do
  include_context "identity issues tokens"

  let(:admin) { bearer(access_token(principal_id: "aaaaaaaa-1111-4222-8333-444444444444", role: "admin")) }

  def create_bin(code: "A-01-1", zone: "A", shelf_level: 2)
    post "/api/v1/bins", params: { bin_code: code, zone: zone, shelf_level: shelf_level }, headers: admin
  end

  it "creates a bin" do
    create_bin

    expect(response).to have_http_status(:created)
    expect(WarehouseBin.find_by(bin_code: "A-01-1").shelf_level).to eq(2)
  end

  it "updates a bin that exists" do
    WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1)

    create_bin(zone: "B")

    expect(response).to have_http_status(:ok)
    expect(WarehouseBin.find_by(bin_code: "A-01-1").zone).to eq("B")
  end

  describe "two creates racing on one code" do
    self.use_transactional_tests = false

    def competitor(&block)
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      connection = PG.connect(
        host: config[:host],
        port: config[:port],
        user: config[:username],
        password: config[:password],
        dbname: config[:database]
      )
      yield connection
    ensure
      connection&.close
    end

    def insert_competing_bin
      competitor do |connection|
        connection.exec_params(
          "INSERT INTO warehouse_bins (bin_code, zone, shelf_level, created_at, updated_at) " \
          "VALUES ($1, 'A', 1, now(), now())",
          [ "A-01-1" ]
        )
      end
    end

    after do
      WarehouseBin.where(bin_code: "A-01-1").delete_all
    end

    it "answers the loser of the insert with the bin the winner made, not a 500" do
      inserted = false
      allow_any_instance_of(WarehouseBin).to receive(:_create_record).and_wrap_original do |original, *args, &block|
        unless inserted
          inserted = true
          insert_competing_bin
        end
        original.call(*args, &block)
      end

      create_bin(zone: "C")

      expect(response).to have_http_status(:ok)
      expect(WarehouseBin.where(bin_code: "A-01-1").count).to eq(1)
      expect(WarehouseBin.find_by(bin_code: "A-01-1").zone).to eq("C")
    end

    it "answers the loser of the uniqueness check the same way, not with a 422" do
      allow(WarehouseBin).to receive(:find_or_initialize_by).and_wrap_original do |original, *args, **kwargs|
        found = original.call(*args, **kwargs)
        insert_competing_bin if found.new_record? && WarehouseBin.uncached { WarehouseBin.where(bin_code: "A-01-1").none? }
        found
      end

      create_bin(zone: "D")

      expect(response).to have_http_status(:ok)
      expect(WarehouseBin.find_by(bin_code: "A-01-1").zone).to eq("D")
    end
  end

  it "refuses a bin with no code" do
    create_bin(code: "")

    expect(response).to have_http_status(:unprocessable_content)
  end
end
