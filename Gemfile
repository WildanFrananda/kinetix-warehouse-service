source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

gem "faye-websocket"
gem "barby"
gem "grpc"
# Server reflection, so grpcurl and the platform gates can list and call this service
# without a local copy of the .proto files. Ruby's grpc gem does not ship it.
gem "grpc_reflection"

group :development do
  gem "grpc-tools"
end




gem "dry-container"
gem "dry-auto_inject"

gem "sorbet", group: :development
gem "sorbet-runtime"


# Loads .env so credentials reach the app from the environment rather than from a
# committed default (S1 / P0-SEC-03). config/database.yml now uses ENV.fetch with no
# fallback, so without this the app cannot read its own local configuration.
gem "dotenv-rails", "~> 3.1", groups: [ :development, :test ]


# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.1"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :development, :test do
  gem "tapioca", require: false
  gem "ruby-lsp", require: false
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
end


group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

gem "jwt", "~> 2.9"
# 1.0.14 or later: `identity.v1.GetMerchantInfoResponse.may_sell` arrived there, and this service
# now asks identity whether a principal may trade instead of reading a role claim and guessing.
# An older gem resolves, installs and then raises NoMethodError on the first merchant lookup.
gem "kinetix-contracts", "~> 1.0", ">= 1.0.20"
