Rails.application.routes.draw do
  # Reachable on any host: load balancers call /up by IP address, Caddy
  # (or kamal-proxy) calls the ask endpoint, and webhooks may arrive on
  # an internal hostname.
  get "up" => "rails/health#show", as: :rails_health_check
  get "/caddy/ask", to: "caddy#ask"
  post "/webhooks/saas_domains", to: "saas_domains_webhooks#create"

  # Customers' domains: their status page and nothing else.
  constraints(CustomDomainConstraint) do
    root "status_pages#show", as: :custom_domain_root
    resources :subscriptions, only: :create
    match "*path", to: "status_pages#not_found", via: :all
  end

  # Your own domain (APP_HOSTS): the dashboard.
  root "home#index"
  resources :custom_domains, only: %i[create destroy] do
    post :check, on: :member
  end
end
