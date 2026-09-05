Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :orders, only: [ :create ] do
        collection do
          get :queue
        end
        member do
          patch :status, to: "orders#update_status"
          post :label, to: "orders#generate_label"
        end
        resource :returns, only: [ :create ], controller: "returns"
      end

      resources :returns, only: [] do
        member do
          patch :status, to: "returns#update_status"
        end
      end
    end
  end
  get "/health", to: "health#show"
  get "/login", to: "sessions#new", as: "login"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: "logout"
  get "/scan", to: "scanner#index", as: "scanner"
  post "/scan/verify", to: "scanner#verify", as: "verify_scan"
  get "/orders", to: "orders_dashboard#index"

  post "/orders/manual_create", to: "orders_dashboard#create_manual_order", as: "manual_create_orders"
  post "/orders/emergency_halt", to: "orders_dashboard#emergency_halt", as: "emergency_halt_orders"
  get "/fleet_radar", to: "fleet_radar#index", as: "fleet_radar"
  get "/returns", to: "returns_dashboard#index", as: "returns_dashboard"
  post "/returns/:id/update_status", to: "returns_dashboard#update_status", as: "update_status_returns_dashboard"

  get "/inventory", to: "inventory#index", as: "inventory_dashboard"
  get "/analytics", to: "analytics#index", as: "analytics_dashboard"
  get "/manifests", to: "manifests#index", as: "manifests_dashboard"
  get "/manifests/handover_pdf", to: "manifests#handover_pdf", as: "handover_pdf_manifests"
  get "/settings", to: "settings#index", as: "settings"
  patch "/settings/update_cutoff", to: "settings#update_cutoff", as: "update_cutoff_settings"
  post "/settings/test_ping", to: "settings#test_ping", as: "test_ping_settings"
  get "/support", to: "support#index", as: "support"
  post "/support/create_ticket", to: "support#create_ticket", as: "create_ticket_support"
  post "/support/start_chat", to: "support#start_chat", as: "start_chat_support"

  post "/orders/:id/print_label", to: "orders_dashboard#print_label", as: "print_label_dashboard"
  get "/orders/:id/label_view", to: "orders_dashboard#label_view", as: "label_view_dashboard"
  post "/orders/:id/dispatch_fleet_pulse", to: "orders_dashboard#dispatch_fleet_pulse", as: "dispatch_fleet_pulse_dashboard"
  get "/tracking/:order_number/stream", to: "tracking_stream#stream", as: "tracking_stream"
  patch "/orders/:id/update_status", to: "orders_dashboard#update_status", as: "update_status_dashboard"
end
