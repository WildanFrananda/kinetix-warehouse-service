# typed: false

require_relative "../../app/core/container"

Container.register(:merchant_repository) { MerchantRepository.new }
Container.register(:order_repository) { OrderRepository.new }
Container.register(:create_order_service) do
  Orders::CreateOrderService.new(
    merchant_repository: Container[:merchant_repository],
    order_repository: Container[:order_repository]
  )
end
Container.register(:get_order_queue_service) do
  Orders::GetOrderQueueService.new(
    order_repository: Container[:order_repository]
  )
end
Container.register(:fleet_pulse_grpc_client) { FleetPulse::GrpcClient.new }

Container.register(:request_pickup_service) do
  Couriers::RequestPickupService.new(
    fleet_client: Container[:fleet_pulse_grpc_client]
  )
end

Container.register(:update_order_status_service) do
  Orders::UpdateOrderStatusService.new(
    order_repository: Container[:order_repository],
    request_pickup_service: Container[:request_pickup_service]
  )
end

Container.register(:generate_shipping_label_service) do
  Labels::GenerateShippingLabelService.new(
    order_repository: Container[:order_repository]
  )
end
Container.register(:return_repository) { ReturnRepository.new }
Container.register(:initiate_return_service) do
  Returns::InitiateReturnService.new(
    order_repository: Container[:order_repository],
    return_repository: Container[:return_repository]
  )
end
Container.register(:update_return_status_service) do
  Returns::UpdateReturnStatusService.new(
    return_repository: Container[:return_repository]
  )
end
Container.register(:fleet_pulse_websocket_client) do
  Couriers::FleetPulseWebSocketClient.new(
    order_repository: Container[:order_repository],
    update_order_status_service: Container[:update_order_status_service]
  )
end

Container.register(:verify_scan_barcode_service) do
  Orders::VerifyScanBarcodeService.new(
    order_repository: Container[:order_repository]
  )
end
