# typed: strict
# frozen_string_literal: true

module Views
  module Manifests
    class Index < Views::Base
      extend T::Sig

      sig do
        params(
          dispatched_orders: T.nilable(T::Array[Order]),
          current_merchant: T.nilable(Merchant),
          merchants: T.nilable(T::Array[Merchant])
        ).void
      end
      def initialize(dispatched_orders:, current_merchant:, merchants:)
        @dispatched_orders = T.let(dispatched_orders || [], T::Array[Order])
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @merchants = T.let(merchants || [], T::Array[Merchant])
      end

      sig { void }
      def view_template
        m_id = @current_merchant ? @current_merchant.id : 1

        render Views::Layouts::ApplicationLayout.new(
          title: "Courier Handover Manifests | Fashion Fulfillment OMS",
          current_merchant: @current_merchant,
          merchants: @merchants,
          current_path: manifests_dashboard_path
        ) do
          h2(class: "text-2xl font-bold text-white mb-6 font-sans tracking-tight") { "📄 Courier Handover Manifests & Batch Dispatch" }

          # Action Card Header
          render Components::UI::Card.new(custom_class: "mb-6 border-indigo-500/40") do
            div(class: "flex items-center justify-between flex-wrap gap-4") do
              div do
                h3(class: "text-lg font-bold text-white mb-1 font-sans") { "🚚 FleetPulse Courier Handover Manifest" }
                p(class: "text-xs text-slate-400") do
                  "Export printable A4 official handover manifest (Surat Jalan Serah Terima Paket) for driver signature & barcode verification."
                end
              end

              div do
                a(
                  href: handover_pdf_manifests_path(merchant_id: m_id),
                  target: "_blank",
                  class: "inline-flex items-center gap-2 px-4 py-2.5 text-xs font-semibold rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white shadow-lg shadow-indigo-500/25 transition-all"
                ) do
                  "📄 Print Official Handover Manifest (Surat Jalan PDF)"
                end
              end
            end
          end

          # Manifest Table Card
          render Components::UI::Card.new do
            if @dispatched_orders.empty?
              div(class: "p-8 text-center text-slate-400 text-xs font-medium") { "No packages ready for handover manifest." }
            else
              render_manifest_table(m_id)
            end
          end
        end
      end

      private

      sig { params(m_id: Integer).void }
      def render_manifest_table(m_id)
        div(class: "overflow-x-auto") do
          table(class: "w-full text-left text-xs text-slate-200 border-collapse") do
            thead do
              tr(class: "border-b border-slate-800 text-slate-400 font-semibold uppercase tracking-wider") do
                th(class: "p-3") { "Order #" }
                th(class: "p-3") { "Items Qty" }
                th(class: "p-3") { "Pipeline Status" }
                th(class: "p-3 text-right") { "Action" }
              end
            end

            tbody do
              @dispatched_orders.each do |ord|
                items_qty = ord.fulfillment_task_lines.sum(&:quantity)

                tr(class: "border-b border-slate-800/60 hover:bg-slate-800/40 transition-all duration-150") do
                  td(class: "p-3 font-bold text-indigo-400 font-mono") { "##{ord.order_number}" }
                  td(class: "p-3 font-mono") { "#{items_qty} pcs" }
                  td(class: "p-3") do
                    render Components::UI::Badge.new(status: ord.status)
                  end
                  td(class: "p-3 text-right font-semibold") do
                    a(
                      href: label_view_dashboard_path(ord.id, merchant_id: m_id),
                      target: "_blank",
                      class: "text-emerald-400 hover:text-emerald-300 transition-colors"
                    ) do
                      "🖨️ Thermal Resi"
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
