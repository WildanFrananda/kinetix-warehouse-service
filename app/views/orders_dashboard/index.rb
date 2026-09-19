# typed: strict
# frozen_string_literal: true

module Views
  module OrdersDashboard
    class Index < Views::Base
      extend T::Sig

      sig do
        params(
          task_cards: T.nilable(T::Array[Fulfillment::TaskQueueService::TaskCardData]),
          current_merchant: T.nilable(Merchant),
          merchants: T.nilable(T::Array[Merchant]),
          status_filter: T.nilable(String),
          notice_flash: T.nilable(String),
          alert_flash: T.nilable(String)
        ).void
      end
      def initialize(task_cards:, current_merchant:, merchants:, status_filter: nil, notice_flash: nil, alert_flash: nil)
        @task_cards = T.let(task_cards || [], T::Array[Fulfillment::TaskQueueService::TaskCardData])
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @merchants = T.let(merchants || [], T::Array[Merchant])
        @status_filter = T.let(status_filter, T.nilable(String))
        @notice_flash = T.let(notice_flash, T.nilable(String))
        @alert_flash = T.let(alert_flash, T.nilable(String))
      end

      sig { void }
      def view_template
        render Views::Layouts::ApplicationLayout.new(
          title: "Order Queue Pipeline | Fashion Fulfillment OMS",
          current_merchant: @current_merchant,
          merchants: @merchants,
          current_path: orders_path
        ) do
          render_flash_banners

          # Header Row
          div(class: "flex flex-wrap items-center justify-between gap-4 mb-6") do
            h1(class: "text-3xl font-bold text-white font-sans tracking-tight") { "Order Queue Pipeline" }

            div(class: "flex items-center gap-3") do
              render Components::UI::Button.new(
                variant: "secondary",
                data_toggle: "filter-drawer"
              ) { "⚡ Filter" }
            end
          end

          # Stepper Pipeline Bar
          render_pipeline_stepper

          # Cards Grid
          render_order_cards_grid

          # Modal & Drawer
          render_filter_drawer
        end
      end

      private

      sig { void }
      def render_flash_banners
        if @notice_flash.present?
          div(class: "p-4 mb-6 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-sm font-medium") do
            span { @notice_flash }
          end
        end

        if @alert_flash.present?
          div(class: "p-4 mb-6 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-400 text-sm font-medium") do
            span { @alert_flash }
          end
        end
      end

      sig { void }
      def render_pipeline_stepper
        m_id = @current_merchant ? @current_merchant.id : 1
        sf = @status_filter.to_s

        count_all = @task_cards.size
        count_received = @task_cards.count { |c| c.status == "received" }
        count_packing = @task_cards.count { |c| c.status == "packing" }
        count_packed = @task_cards.count { |c| c.status == "packed" }
        count_cancelled = @task_cards.count { |c| c.status == "cancelled" }

        div(class: "flex flex-wrap items-center gap-3 mb-8") do
          render_step_pill("All Orders (#{count_all})", orders_path(merchant_id: m_id), sf.empty?)
          span(class: "text-slate-600 font-bold") { "—" }
          render_step_pill("1. Received (#{count_received})", orders_path(merchant_id: m_id, status_filter: "received"), sf == "received")
          span(class: "text-slate-600 font-bold") { "—" }
          render_step_pill("2. Packing (#{count_packing})", orders_path(merchant_id: m_id, status_filter: "packing"), sf == "packing")
          span(class: "text-slate-600 font-bold") { "—" }
          render_step_pill("3. Packed (#{count_packed})", orders_path(merchant_id: m_id, status_filter: "packed"), sf == "packed")
          span(class: "text-slate-600 font-bold") { "—" }
          render_step_pill("4. Cancelled (#{count_cancelled})", orders_path(merchant_id: m_id, status_filter: "cancelled"), sf == "cancelled")
        end
      end

      sig { params(label: String, path: String, is_active: T::Boolean).void }
      def render_step_pill(label, path, is_active)
        pill_class = if is_active
                       "px-3.5 py-1.5 text-xs font-semibold rounded-lg bg-indigo-600 text-white border border-indigo-500 shadow-md"
        else
                       "px-3.5 py-1.5 text-xs font-medium rounded-lg bg-slate-800/60 text-slate-400 hover:bg-slate-700/60 border border-slate-700/50"
        end

        a(href: path, class: pill_class) { label }
      end

      sig { void }
      def render_order_cards_grid
        sf = @status_filter.to_s
        filtered = sf.present? ? @task_cards.select { |c| c.status == sf } : @task_cards

        if filtered.empty?
          div(class: "p-12 text-center rounded-2xl bg-slate-900/60 border border-slate-800 text-slate-400 text-sm font-medium") do
            "No active orders found in this pipeline stage."
          end
        else
          div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6", id: "order-queue-grid") do
            filtered.each do |card|
              render_single_order_card(card)
            end
          end
        end
      end

      sig { params(card: Fulfillment::TaskQueueService::TaskCardData).void }
      def render_single_order_card(card)
        m_id = @current_merchant ? @current_merchant.id : 1

        render Components::UI::Card.new(custom_class: "flex flex-col justify-between h-full") do
          div do
            # Card Top Header Meta
            div(class: "flex items-start justify-between mb-4 pb-3 border-b border-slate-800/80") do
              div do
                span(class: "text-base font-bold text-white font-mono") { "##{card.order_number}" }
                div(class: "text-xs text-slate-400 mt-0.5") do
                  created_at = card.created_at
                  created_at ? created_at.strftime("%a, %I:%M %p") : Time.current.strftime("%a, %I:%M %p")
                end
              end

              div(class: "flex items-center gap-2") do
                render Components::UI::Badge.new(status: card.status)
              end
            end

            # Customer Details Box
            div(class: "p-3 mb-4 rounded-lg bg-slate-950/50 border border-slate-800/60") do
              div(class: "flex items-start gap-2.5") do
                span(class: "text-base") { "👤" }
                div do
                  div(class: "text-sm font-semibold text-white") { card.order_number }
                end
              end
            end

            # Manifest Box
            div(class: "mb-4") do
              div(class: "text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2") { "Manifest" }

              div(class: "p-3 rounded-lg bg-slate-950/60 border border-slate-800/60 space-y-2") do
                card.lines.each do |item|
                  div(class: "flex items-center justify-between text-xs") do
                    span(class: "font-medium text-slate-200") { "#{item.quantity}x" }
                    span(class: "font-mono text-slate-400 text-[11px]") { "SKU: #{item.sku}" }
                  end

                  div(class: "text-[11px] font-medium text-emerald-400") do
                    "📍 Location: #{item.bin_location.presence || "no bin recorded"}"
                  end
                end
              end
            end
          end

          # Bottom Action Row
          div(class: "pt-4 border-t border-slate-800/80 mt-2") do
            if card.status == "received" || card.status == "packing"
              div(class: "flex items-center gap-2") do
                a(
                  href: scanner_path(merchant_id: m_id, order_id: card.id),
                  class: "flex-1 inline-flex items-center justify-center px-3 py-2 text-xs font-semibold rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white shadow-md transition-all"
                ) do
                  "📱 Scan Order"
                end

                form(action: update_status_dashboard_path(card.id, merchant_id: m_id, status: "packed"), method: "post", class: "inline-block") do
                  input(type: "hidden", name: "_method", value: "patch")
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                  render Components::UI::Button.new(variant: "secondary", type: "submit") { "📦" }
                end

                a(
                  href: label_view_dashboard_path(card.id, merchant_id: m_id),
                  target: "_blank",
                  class: "inline-flex items-center justify-center p-2 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700"
                ) do
                  "🖨️"
                end
              end
            elsif card.status == "packed"
              div(class: "flex items-center gap-2") do
                a(
                  href: label_view_dashboard_path(card.id, merchant_id: m_id),
                  target: "_blank",
                  class: "flex-1 inline-flex items-center justify-center p-2 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700"
                ) do
                  "🖨️"
                end
              end
            end
          end
        end
      end

      sig { void }
      def render_filter_drawer
        m_id = @current_merchant ? @current_merchant.id : 1

        div(id: "filter-drawer", class: "drawer-overlay hidden fixed inset-0 z-50 bg-slate-950/80 backdrop-blur-md flex justify-end") do
          div(class: "drawer-panel w-full max-w-md bg-slate-900 border-l border-slate-800 h-full p-6 overflow-y-auto") do
            div(class: "flex items-center justify-between mb-6 pb-4 border-b border-slate-800") do
              h2(class: "text-lg font-bold text-white font-sans") { "⚡ Filter Order Queue" }
              button(type: "button", class: "text-slate-400 hover:text-white text-xl font-bold", data_close: "filter-drawer") { "×" }
            end

            form(action: orders_path, method: "get", class: "space-y-6") do
              input(type: "hidden", name: "merchant_id", value: m_id.to_s)

              div do
                label(class: "block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2") { "Order Status" }
                div(class: "grid grid-cols-2 gap-2") do
                  [ "received", "packing", "packed", "cancelled" ].each do |st|
                    label(class: "flex items-center gap-2 p-2 rounded-lg bg-slate-950 border border-slate-800/80 cursor-pointer text-xs font-medium text-slate-200") do
                      input(type: "checkbox", name: "status_filter[]", value: st, class: "rounded border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500")
                      span { st.tr("_", " ").capitalize }
                    end
                  end
                end
              end

              div(class: "flex items-center justify-between gap-3 pt-6 border-t border-slate-800") do
                a(href: orders_path(merchant_id: m_id), class: "px-4 py-2 text-xs font-semibold text-slate-400 hover:text-white border border-slate-800 rounded-lg") { "Reset All" }
                render Components::UI::Button.new(variant: "primary", type: "submit") { "Apply Filters →" }
              end
            end
          end
        end
      end
    end
  end
end
