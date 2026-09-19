# typed: strict

require "socket"
require "timeout"
require "net/http"
require "uri"

class SupportController < ApplicationController
  extend T::Sig

  sig { void }
  def index
    merchant_id_param = params[:merchant_id]
    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchants = Merchant.order(:name).to_a
    @merchants = T.let(merchants, T.nilable(T::Array[Merchant]))

    merchant_id = active_merchant_id
    selected_merchant = merchant_repo.find_by_id(merchant_id)

    @current_merchant = T.let(selected_merchant || merchants.first, T.nilable(Merchant))

    current = @current_merchant
    merchant_id = current ? current.id : 1

    # 1. Real PostgreSQL Database Check
    db_connected = ActiveRecord::Base.connection.active?
    @db_healthy = T.let(db_connected, T.nilable(T::Boolean))

    # 2. Real ActionCable WebSocket Handshake Test to /cable
    action_cable_online = false
    begin
      cable_uri = URI.parse("#{request.base_url}/cable")
      http = Net::HTTP.new(T.must(cable_uri.host), T.must(cable_uri.port))
      http.open_timeout = 0.2
      http.read_timeout = 0.2

      req = Net::HTTP::Get.new(cable_uri.path.presence || "/cable")

      req["Upgrade"] = "websocket"
      req["Connection"] = "Upgrade"
      req["Sec-WebSocket-Key"] = Base64.strict_encode64(SecureRandom.random_bytes(16))
      req["Sec-WebSocket-Version"] = "13"


      res = http.request(req)
      # ActionCable returns HTTP 101 (Switching Protocols) or 400 Bad Request if handshake validates
      action_cable_online = (res.code.to_i == 101 || res.code.to_i == 400 || res.code.to_i == 422)
    rescue StandardError
      action_cable_online = false
    end
    @action_cable_healthy = T.let(action_cable_online, T.nilable(T::Boolean))

    # 3. Real Socket Ping Execution to Phoenix Server (Port 4000)
    phoenix_host = ENV.fetch("FLEETPULSE_PHOENIX_HOST", "localhost")
    phoenix_port = ENV.fetch("FLEETPULSE_PHOENIX_PORT", "4000").to_i

    phoenix_online = false
    measured_ping = T.let(nil, T.nilable(Integer))

    begin
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Timeout.timeout(0.2) do
        socket = TCPSocket.new(phoenix_host, phoenix_port)
        socket.close
      end
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      phoenix_online = true
      latency_ms = ((end_time - start_time) * 1000).round
      measured_ping = latency_ms.zero? ? 1 : latency_ms
    rescue StandardError
      phoenix_online = false
      measured_ping = nil
    end

    render Views::Support::Index.new(
      action_cable_healthy: action_cable_online,
      phoenix_healthy: phoenix_online,
      phoenix_ping_ms: measured_ping || 0,
      db_healthy: db_connected,
      base_url: request.base_url,
      current_merchant: @current_merchant,
      merchants: @merchants,
      notice_flash: flash[:notice],
      alert_flash: flash[:alert]
    ), layout: false
  end
end
