require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Components; end
module Views; end
module Rpc; end

module FashionFulfillmentOms
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks generated kinetix/metrics.rb kinetix/metrics])

    require_relative "../lib/kinetix/request_id_middleware"
    config.middleware.insert_after ActionDispatch::RequestId, Kinetix::RequestIdMiddleware

    require_relative "../lib/kinetix/metrics/http_middleware"
    config.middleware.unshift Kinetix::Metrics::HttpMiddleware

    Rails.autoloaders.main.inflector.inflect("ui" => "UI")

    app_root = File.expand_path("..", __dir__)
    Rails.autoloaders.main.push_dir("#{app_root}/app/components", namespace: Components)
    Rails.autoloaders.main.push_dir("#{app_root}/app/views", namespace: Views)
    Rails.autoloaders.main.push_dir("#{app_root}/app/rpc", namespace: Rpc)
  end
end
