# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "what another service sees when warehouse fails a gRPC call" do
  include_context "warehouse serves gRPC over mTLS"

  let(:principal) { "cccccccc-1111-4222-8333-777777777777" }
  let(:metadata) { { Kinetix::RequestId::HEADER => "req-grpc-failure-1" } }

  def check_stock
    stock("catalog").check_bin_stock(
      Fulfillment::V1::CheckBinStockRequest.new(merchant_principal_id: principal, sku: "S"),
      metadata: metadata
    )
  end

  before { allow(Rails.logger).to receive(:error).and_call_original }

  context "when warehouse cannot reach its database" do
    self.use_transactional_tests = false

    around do |example|
      live = ActiveRecord::Base.connection_db_config
      ActiveRecord::Base.establish_connection(live.configuration_hash.merge(host: "127.0.0.1", port: 1))
      example.run
    ensure
      ActiveRecord::Base.establish_connection(live)
    end

    it "answers UNAVAILABLE in a fixed sentence, never the database's host" do
      expect { check_stock }.to raise_error(GRPC::Unavailable) { |error|
        expect(error.details).to eq("warehouse could not reach its database; try again shortly")
      }
    end

    it "logs what went wrong under the caller's request id" do
      expect { check_stock }.to raise_error(GRPC::Unavailable)

      expect(Rails.logger).to have_received(:error)
        .with(a_string_matching(/request_id=req-grpc-failure-1.*ActiveRecord::DatabaseConnectionError/))
    end

    it "answers a write the same way" do
      request = Fulfillment::V1::ReserveStockRequest.new(
        merchant_principal_id: principal, sku: "S", quantity: 1, order_number: "ORD-OUTAGE-1"
      )

      expect { stock.reserve_stock(request) }.to raise_error(GRPC::Unavailable) { |error|
        expect(error.details).not_to match(/127\.0\.0\.1|hostname|ActiveRecord|PG::/)
      }
    end
  end

  context "when a handler fails for any other reason" do
    let(:broken) do
      Class.new(MerchantRepository) do
        def find_by_principal_id(_principal_id)
          raise "row 42 on pgsql-node is corrupt"
        end
      end
    end

    before do
      allow(Container).to receive(:[]).and_call_original
      allow(Container).to receive(:[]).with(:merchant_repository).and_return(broken.new)
    end

    it "answers INTERNAL in a fixed sentence, never the exception's class or text" do
      expect { check_stock }.to raise_error(GRPC::Internal) { |error|
        expect(error.details).to eq("warehouse failed while handling this call")
      }
    end

    it "logs the exception under the caller's request id" do
      expect { check_stock }.to raise_error(GRPC::Internal)

      expect(Rails.logger).to have_received(:error)
        .with(a_string_matching(/request_id=req-grpc-failure-1.*RuntimeError: row 42 on pgsql-node is corrupt/))
    end
  end

  context "when warehouse refuses a call on purpose" do
    it "keeps its own status and sentence" do
      request = Fulfillment::V1::CheckBinStockBatchRequest.new(
        merchant_principal_id: principal,
        skus: Array.new(201) { |index| "SKU-#{index}" }
      )

      expect { stock("catalog").check_bin_stock_batch(request) }.to raise_error(GRPC::InvalidArgument) { |error|
        expect(error.details).to eq("asked about 201 skus; this call answers at most 200")
      }
    end

    it "names a tracking number already on another parcel in fixed words, not a validation message" do
      merchant = create(:merchant, principal_id: principal)
      labelled = create(:fulfillment_task, merchant: merchant, status: "packed")
      create(:shipping_label, fulfillment_task: labelled, awb_number: "KNX-20261027-TAKEN")
      task = create(:fulfillment_task, merchant: merchant, status: "packed")

      res = tasks.record_courier_awb(
        Fulfillment::V1::RecordCourierAwbRequest.new(
          merchant_principal_id: principal,
          fulfillment_task_id: task.id.to_s,
          awb_number: "KNX-20261027-TAKEN"
        )
      )

      expect(res.accepted).to be(false)
      expect(res.error.error_code).to eq("AWB_REFUSED")
      expect(res.error.message).to eq("that tracking number is already on another parcel")
      expect(task.reload.shipping_label).to be_nil
    end
  end
end
