# typed: strict
# frozen_string_literal: true

module Views
  module Analytics
    class Index < Views::Base
      extend T::Sig

      sig do
        params(
          sla_compliance_rate: Float,
          total_orders: Integer,
          overdue_orders_count: Integer,
          top_skus: T.nilable(T::Array[AnalyticsController::TopSkuData]),
          current_merchant: T.nilable(Merchant),
          merchants: T.nilable(T::Array[Merchant])
        ).void
      end
      def initialize(sla_compliance_rate:, total_orders:, overdue_orders_count:, top_skus:, current_merchant:, merchants:)
        @sla_compliance_rate = T.let(sla_compliance_rate, Float)
        @total_orders = T.let(total_orders, Integer)
        @overdue_orders_count = T.let(overdue_orders_count, Integer)
        @top_skus = T.let(top_skus || [], T::Array[AnalyticsController::TopSkuData])
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @merchants = T.let(merchants || [], T::Array[Merchant])
      end

      sig { void }
      def view_template
        render Views::Layouts::ApplicationLayout.new(
          title: "SLA Analytics & Performance | Fashion Fulfillment OMS",
          current_merchant: @current_merchant,
          merchants: @merchants,
          current_path: analytics_dashboard_path
        ) do
          h2(class: "text-2xl font-bold text-white mb-6 font-sans tracking-tight") { "📊 SLA Compliance & Logistics KPI Performance" }

          # KPI Cards Grid
          div(class: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6 mb-8") do
            render_kpi_card("🎯 SLA ON-TIME RATE", "#{@sla_compliance_rate}%", "Same-Day Cutoff Compliance Target: > 95%", "text-indigo-400", "border-indigo-500/30")
            render_kpi_card("📦 TOTAL ACTIVE ORDERS", @total_orders.to_s, "Open Fulfillment Pipeline", "text-emerald-400", "border-emerald-500/30")
            render_kpi_card("🚨 OVERDUE SLA VIOLATIONS", @overdue_orders_count.to_s, "Requires Immediate Warehouse Dispatch", "text-rose-400", "border-rose-500/30")
          end

          # Top Products Ranking
          h3(class: "text-lg font-bold text-white mb-4 font-sans tracking-tight") { "🏆 Top Selling Fashion Products Ranking" }

          render Components::UI::Card.new do
            if @top_skus.empty?
              div(class: "p-8 text-center text-slate-400 text-xs font-medium") { "No sales data recorded yet." }
            else
              render_top_skus_table
            end
          end
        end
      end

      private

      sig { params(title: String, value: String, subtitle: String, color_class: String, border_class: String).void }
      def render_kpi_card(title, value, subtitle, color_class, border_class)
        render Components::UI::Card.new(custom_class: "text-center #{border_class}") do
          div(class: "text-xs font-bold text-slate-400 uppercase tracking-wider mb-2") { title }
          div(class: "text-3xl font-extrabold #{color_class} tracking-tight font-mono mb-1") { value }
          div(class: "text-[11px] text-slate-400 font-medium") { subtitle }
        end
      end

      sig { void }
      def render_top_skus_table
        div(class: "overflow-x-auto") do
          table(class: "w-full text-left text-xs text-slate-200 border-collapse") do
            thead do
              tr(class: "border-b border-slate-800 text-slate-400 font-semibold uppercase tracking-wider") do
                th(class: "p-3") { "Rank" }
                th(class: "p-3") { "SKU" }
                th(class: "p-3 text-center") { "Units Picked" }
              end
            end

            tbody do
              @top_skus.each_with_index do |prod, idx|
                tr(class: "border-b border-slate-800/60 hover:bg-slate-800/40 transition-all duration-150") do
                  td(class: "p-3 font-bold text-amber-400 font-mono") { "##{idx + 1}" }
                  td(class: "p-3 font-mono text-slate-300") { prod.sku }
                  td(class: "p-3 text-center font-bold text-emerald-400") { "#{prod.total_units_picked} pcs" }
                end
              end
            end
          end
        end
      end

      sig { params(val: Integer).returns(String) }
      def format_number(val)
        val.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1.').reverse
      end
    end
  end
end
