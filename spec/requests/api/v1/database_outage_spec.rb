# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "what a client sees when warehouse cannot reach its database", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  self.use_transactional_tests = false

  let(:seller) { bearer(access_token(principal_id: "11111111-2222-3333-4444-aaaaaaaaaaaa")) }
  let(:json) { { "Content-Type" => "application/json" } }
  let(:admin) do
    bearer(access_token(principal_id: "aaaaaaaa-1111-4222-8333-aaaaaaaaaaaa", role: "admin")).merge(json)
  end

  def with_database_unreachable
    live = ActiveRecord::Base.connection_db_config
    ActiveRecord::Base.establish_connection(live.configuration_hash.merge(host: "127.0.0.1", port: 1))
    yield
  ensure
    ActiveRecord::Base.establish_connection(live)
  end

  def expect_database_unavailable
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Retry-After"]).to eq("15")
    body = response.parsed_body
    expect(body["error"]).to eq("DATABASE_UNAVAILABLE")
    expect(body["message"]).to eq(
      "warehouse could not reach its database, so this request could not be completed. Try again shortly."
    )
    expect(body["traceId"]).to be_present
    expect(response.body).not_to match(/127\.0\.0\.1|hostname|PG::|ConnectionNotEstablished/)
  end

  it "answers a seller's request 503 DATABASE_UNAVAILABLE with Retry-After" do
    with_database_unreachable { get "/api/v1/fulfillment_tasks/queue", headers: seller }

    expect_database_unavailable
  end

  it "answers a staff request 503 DATABASE_UNAVAILABLE, and the admin action is recorded as failed" do
    allow(Kinetix::Metrics::AdminActions).to receive(:record)

    with_database_unreachable do
      post "/api/v1/bins", params: { bin_code: "OUTAGE-1", zone: "A" }.to_json, headers: admin
    end

    expect_database_unavailable
    expect(Kinetix::Metrics::AdminActions)
      .to have_received(:record).with(action: Kinetix::Metrics::AdminActions::BIN_UPSERT, outcome: "failed")
  end

  it "keeps a failure that is not the database's connection a 500" do
    failing = Class.new(Fulfillment::TaskQueueService) do
      def call(merchant_id:)
        ActiveRecord::Base.connection.select_value("SELECT 1 / (#{merchant_id} - #{merchant_id})")
      end
    end
    queue = failing.new(task_repository: Container[:fulfillment_task_repository])
    allow(Container).to receive(:[]).with(:task_queue_service).and_return(queue)

    get "/api/v1/fulfillment_tasks/queue", headers: seller

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body["error"]).to eq("INTERNAL_ERROR")
    expect(response.headers["Retry-After"]).to be_nil
  ensure
    Merchant.delete_all
  end
end
