Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :fulfillment_tasks, only: [ :index ] do
        collection do
          get :queue
        end
        member do
          patch :status, to: "fulfillment_tasks#update_status"
          post :label, to: "fulfillment_tasks#generate_label"
          post :verify_scan, to: "fulfillment_tasks#verify_scan"
        end
        resource :returns, only: [ :create ], controller: "returns"
      end

      post "/returns/:return_number/received", to: "returns#received"

      resources :merchants, only: [ :update ] do
        collection do
          get :me
        end
      end
      get "bins/stock", to: "bin_stock#index"
      resources :bins, only: [ :index, :create ]
      resources :stock_receipts, only: [ :index, :create ]
      resources :stock_adjustments, only: [ :index, :create ]
    end
  end

  get "/metrics", to: "metrics#show"
  get "/health", to: "health#show"
  get "/health/ready", to: "health#ready"
end
