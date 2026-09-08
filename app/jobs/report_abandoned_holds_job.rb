# typed: strict
# frozen_string_literal: true

class ReportAbandonedHoldsJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    Inventory::AbandonedHoldReport.new.call
  end
end
