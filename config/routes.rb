Rails.application.routes.draw do
  # This service has no pages. It had eight controllers rendering HTML — a sign-in form, a scanner,
  # an orders board, returns, analytics, manifests, settings and a support console — and none of them
  # was ever routed through the gateway, so none was reachable. Every admin screen belongs to the
  # backoffice, which talks to the API below. (docs/BOUNDARY-DEBT.md W12, W1, W9)
  namespace :api do
    namespace :v1 do
      resources :fulfillment_tasks, only: [] do
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

      resources :returns, only: [] do
        member do
          patch :status, to: "returns#update_status"
        end
      end

      resources :merchants, only: [ :update ]
      resources :bins, only: [ :create ]
      resources :stock_receipts, only: [ :create ]
      resources :stock_adjustments, only: [ :create ]
    end
  end

  get "/metrics", to: "metrics#show"
  get "/health", to: "health#show"
  get "/health/ready", to: "health#ready"
end
