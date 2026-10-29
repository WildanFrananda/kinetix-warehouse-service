# typed: strict
# frozen_string_literal: true

module ApiLedgerQuery
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ActionController::Base }

  DEFAULT_LIMIT = 50
  MAX_LIMIT = 100

  class BadQuery < StandardError
    extend T::Sig

    sig { returns(String) }
    attr_reader :code

    sig { params(field: Symbol, message: String).void }
    def initialize(field, message)
      super(message)
      @code = T.let("INVALID_#{field.upcase}", String)
    end
  end

  included do
    T.bind(self, T.class_of(ActionController::Base))

    rescue_from BadQuery, with: :render_bad_query
  end

  private

  sig { returns(Inventory::StockLedgerService) }
  def ledger
    T.let(Container[:stock_ledger_service], Inventory::StockLedgerService)
  end

  sig { returns(Inventory::StockFilter) }
  def stock_filter
    Inventory::StockFilter.new(
      sku: query_text(:sku, StockOperation::MAX_SKU_LENGTH),
      bin_code: query_text(:bin_code, WarehouseBin::MAX_CODE_LENGTH),
      merchant_principal_id: query_principal(:merchant_principal_id)
    )
  end

  sig { returns(Integer) }
  def page_limit
    raw = params[:limit]
    return DEFAULT_LIMIT if raw.nil?

    limit = raw.is_a?(String) ? Kinetix::IntegerParam.parse(raw, signed: false) : nil
    return limit if limit&.between?(1, MAX_LIMIT)

    raise BadQuery.new(:limit, "limit must be a whole number from 1 to #{MAX_LIMIT}, written in digits")
  end

  sig { params(name: Symbol, max: Integer).returns(T.nilable(String)) }
  def query_text(name, max)
    value = params[name]
    return nil if value.nil?
    return value if value.is_a?(String) && !value.include?(ApiStringParams::NUL) && value.length.between?(1, max)

    raise BadQuery.new(name, "#{name} must be one string of 1 to #{max} characters")
  end

  sig { params(name: Symbol).returns(T.nilable(String)) }
  def query_principal(name)
    value = params[name]
    return nil if value.nil?

    canonical = value.is_a?(String) ? Kinetix::PrincipalId.canonical(value) : nil
    return canonical unless canonical.nil?

    raise BadQuery.new(name, "#{name} must be a UUID")
  end

  sig { params(name: Symbol).returns(T.nilable(Integer)) }
  def query_id(name)
    value = params[name]
    return nil if value.nil?

    id = Kinetix::IntegerParam.id(value)
    return id unless id.nil?

    raise BadQuery.new(name, "#{name} must be a record id written in digits")
  end

  sig { params(exception: BadQuery).void }
  def render_bad_query(exception)
    render(json: { error: exception.code, message: exception.message }, status: :bad_request)
  end
end
