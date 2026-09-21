# typed: false

require_relative "../../app/core/container"

Container.register(:merchant_repository) { MerchantRepository.new }
Container.register(:fulfillment_task_repository) { FulfillmentTaskRepository.new }

Container.register(:create_task_service) do
  Fulfillment::CreateTaskService.new(
    merchant_repository: Container[:merchant_repository],
    task_repository: Container[:fulfillment_task_repository]
  )
end
Container.register(:task_queue_service) do
  Fulfillment::TaskQueueService.new(
    task_repository: Container[:fulfillment_task_repository]
  )
end

Container.register(:order_grpc_client) { Order::GrpcClient.new }
Container.register(:identity_grpc_client) { Identity::GrpcClient.new }

Container.register(:resolve_merchant_service) do
  Merchants::ResolveService.new(
    merchant_repository: Container[:merchant_repository],
    identity_client: Container[:identity_grpc_client]
  )
end

Container.register(:advance_task_service) do
  Fulfillment::AdvanceTaskService.new(
    task_repository: Container[:fulfillment_task_repository],
    order_client: Container[:order_grpc_client]
  )
end
Container.register(:verify_scan_service) do
  Fulfillment::VerifyScanService.new(
    task_repository: Container[:fulfillment_task_repository]
  )
end

Container.register(:generate_shipping_label_service) do
  Labels::GenerateShippingLabelService.new(
    task_repository: Container[:fulfillment_task_repository]
  )
end
