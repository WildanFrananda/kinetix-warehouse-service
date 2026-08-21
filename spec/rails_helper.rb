# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require_relative '../app/clients/identity_client'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!

  config.before(:each) do
    allow_any_instance_of(Identity::GrpcClient).to receive(:get_merchant_by_api_key) do |_instance, api_key|
      if api_key.nil? || api_key.empty? || api_key.to_s.upcase.include?("INVALID")
        nil
      else
        {
          user_id: 101,
          store_name: "Kinetix Store",
          business_registration_number: "REG-12345",
          tax_id: "TAX-998877",
          status: "verified"
        }
      end
    end

    allow_any_instance_of(Identity::GrpcClient).to receive(:get_user_profile).and_return({
      user_id: 101,
      email: "user_101@kinetix.com",
      full_name: "Customer 101",
      phone_number: "081234567890",
      street_address: "Jl. Sudirman 101",
      city: "Jakarta",
      postal_code: "10220",
      role: "customer"
    })
  end
end
