# typed: false
# frozen_string_literal: true

RSpec.shared_context "a migration runs inside each example" do
  def forget_schema
    ActiveRecord::Base.connection.schema_cache.clear!
    ApplicationRecord.descendants.each(&:reset_column_information)
  end

  before { forget_schema }

  after { forget_schema }
end
