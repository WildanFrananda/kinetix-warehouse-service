# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "the audit of what admins do here", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:staff) { "aaaaaaaa-1111-4222-8333-444444444444" }
  let(:owner) { "bbbbbbbb-1111-4222-8333-444444444444" }
  let(:request_id) { "kinetix-spec-audit-0001" }
  let(:admin) { bearer(access_token(principal_id: staff, role: "admin")).merge("X-Request-Id" => request_id) }
  let(:logged) { [] }
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  before do
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
      logged << args.first if args.first.is_a?(String)
      original.call(*args, &block)
    end
  end

  def audit_lines
    logged.select { |line| line.start_with?("admin_action ") }
  end

  def count(action, outcome)
    sample = Kinetix::Metrics.collection.admin_actions.samples.find do |candidate|
      candidate.labels == { "action" => action, "outcome" => outcome }
    end

    sample&.value.to_f
  end

  def receipt(headers: admin, bin_code: "A-01-1", key: "RCV-1")
    post "/api/v1/stock_receipts",
         params: {
           bin_code: bin_code,
           sku: "SKU-1",
           quantity: 5,
           idempotency_key: key,
           merchant_principal_id: owner
         },
         headers: headers
  end

  it "records a bin upsert as done, with who did it, what and to which bin" do
    before = count("warehouse.bin_upsert", "done")

    post "/api/v1/bins", params: { bin_code: "B-02-1", zone: "B" }, headers: admin

    expect(response).to have_http_status(:created)
    expect(audit_lines).to eq(
      [
        "admin_action actor=#{staff} action=warehouse.bin_upsert target=\"B-02-1\" outcome=done " \
        "request_id=#{request_id}"
      ]
    )
    expect(count("warehouse.bin_upsert", "done")).to eq(before + 1)
  end

  it "records a stock receipt as done, its target the shelf slot it booked into" do
    before = count("warehouse.stock_receive", "done")

    receipt

    expect(response).to have_http_status(:created)
    expect(audit_lines).to eq(
      [
        "admin_action actor=#{staff} action=warehouse.stock_receive target=\"A-01-1/SKU-1\" outcome=done " \
        "request_id=#{request_id}"
      ]
    )
    expect(count("warehouse.stock_receive", "done")).to eq(before + 1)
  end

  it "records a receipt it refused as refused" do
    before = count("warehouse.stock_receive", "refused")

    receipt(bin_code: "NO-SUCH-BIN")

    expect(response).to have_http_status(:unprocessable_content)
    expect(audit_lines.size).to eq(1)
    expect(audit_lines.first).to include("action=warehouse.stock_receive", "outcome=refused")
    expect(count("warehouse.stock_receive", "refused")).to eq(before + 1)
  end

  context "when identity cannot be asked about the owner" do
    let(:identity_client) { FakeIdentityClient.new(unavailable: true) }

    it "records the receipt as failed, not refused" do
      before = count("warehouse.stock_receive", "failed")

      receipt

      expect(response).to have_http_status(:service_unavailable)
      expect(audit_lines.size).to eq(1)
      expect(audit_lines.first).to include("outcome=failed")
      expect(count("warehouse.stock_receive", "failed")).to eq(before + 1)
    end
  end

  it "records an adjustment, and a body it could not read as refused" do
    BinInventory.create!(
      warehouse_bin: bin,
      sku: "SKU-1",
      quantity: 10,
      reserved_quantity: 0,
      merchant_principal_id: owner
    )
    done = count("warehouse.stock_adjust", "done")
    refused = count("warehouse.stock_adjust", "refused")

    post "/api/v1/stock_adjustments",
         params: {
           bin_code: "A-01-1",
           sku: "SKU-1",
           quantity_delta: -2,
           reason: "DAMAGE",
           idempotency_key: "ADJ-1",
           merchant_principal_id: owner
         },
         headers: admin
    post "/api/v1/stock_adjustments",
         params: "{\"quantity_delta\": ",
         headers: admin.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:bad_request)
    expect(audit_lines.map { |line| line[/outcome=\w+/] }).to eq([ "outcome=done", "outcome=refused" ])
    expect(audit_lines.last).to include("action=warehouse.stock_adjust", "target=\"-\"")
    expect(count("warehouse.stock_adjust", "done")).to eq(done + 1)
    expect(count("warehouse.stock_adjust", "refused")).to eq(refused + 1)
  end

  it "quotes a target it was sent, so the target cannot forge the fields after it" do
    post "/api/v1/bins", params: { bin_code: "X outcome=done actor=nobody", zone: "B" }, headers: admin

    expect(audit_lines.first).to include("target=\"X outcome=done actor=nobody\" outcome=done")
    expect(audit_lines.first.scan("actor=").size).to eq(2)
    expect(audit_lines.first).to start_with("admin_action actor=#{staff} ")
  end

  it "does not count a seller turned away as an admin action" do
    receipt(headers: bearer(access_token(principal_id: staff, role: "seller")))

    expect(response).to have_http_status(:forbidden)
    expect(audit_lines).to be_empty
  end

  it "publishes every action and outcome at zero before any happens" do
    get "/metrics"

    %w[warehouse.bin_upsert warehouse.stock_receive warehouse.stock_adjust].each do |action|
      %w[done refused failed].each do |outcome|
        expect(response.body).to match(
          /^kinetix_admin_actions_total\{action="#{Regexp.escape(action)}",outcome="#{outcome}"\} \d/
        )
      end
    end
  end
end
