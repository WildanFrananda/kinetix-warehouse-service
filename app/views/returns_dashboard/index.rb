# typed: strict
# frozen_string_literal: true

module Views
  module ReturnsDashboard
    class Index < Views::Base
      extend T::Sig

      sig do
        params(
          return_items: T.nilable(T::Array[Return]),
          current_merchant: T.nilable(Merchant),
          merchants: T.nilable(T::Array[Merchant]),
          notice_flash: T.nilable(String),
          alert_flash: T.nilable(String)
        ).void
      end
      def initialize(return_items:, current_merchant:, merchants:, notice_flash: nil, alert_flash: nil)
        @return_items = T.let(return_items || [], T::Array[Return])
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @merchants = T.let(merchants || [], T::Array[Merchant])
        @notice_flash = T.let(notice_flash, T.nilable(String))
        @alert_flash = T.let(alert_flash, T.nilable(String))
      end

      sig { void }
      def view_template
        render Views::Layouts::ApplicationLayout.new(
          title: "Returns & Exchange Hub | Fashion Fulfillment OMS",
          current_merchant: @current_merchant,
          merchants: @merchants,
          current_path: returns_dashboard_path
        ) do
          render_flash_banners

          h2(class: "text-2xl font-bold text-white mb-6 font-sans tracking-tight") { "📋 Customer Return & Exchange Claims" }

          if @return_items.empty?
            div(class: "p-12 text-center rounded-2xl bg-slate-900/60 border border-slate-800 text-slate-400 text-sm font-medium") do
              "No return claims submitted for this merchant."
            end
          else
            div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
              @return_items.each do |ret|
                render_single_return_card(ret)
              end
            end
          end
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

      sig { params(ret: Return).void }
      def render_single_return_card(ret)
        m_id = @current_merchant ? @current_merchant.id : 1
        ord = ret.order

        render Components::UI::Card.new(custom_class: "flex flex-col justify-between h-full border-rose-500/30") do
          div do
            div(class: "flex items-center justify-between mb-4 pb-3 border-b border-slate-800") do
              span(class: "text-base font-bold text-white font-mono") { "🔄 Return #RET-#{ret.id}" }
              render Components::UI::Badge.new(status: ret.status)
            end

            div(class: "text-xs text-slate-300 mb-1") do
              "📦 Associated Order: "
              strong(class: "text-white font-mono") { ord ? "##{ord.order_number}" : "-" }
            end

            div(class: "text-xs text-slate-400 mb-4") do
              "👤 Customer: "
              strong(class: "text-slate-200") { ord ? ord.order_number : "-" }
                          end

            div(class: "p-3 rounded-lg bg-rose-500/10 border border-rose-500/20 mb-4") do
              div(class: "text-[11px] font-bold text-rose-400 uppercase tracking-wider mb-1") { "Customer Return Reason:" }
              div(class: "text-xs text-rose-200 italic") { "\"#{ret.reason}\"" }
            end
          end

          div(class: "pt-4 border-t border-slate-800 mt-2") do
            render_state_machine_button(ret, m_id)
          end
        end
      end

      sig { params(ret: Return, m_id: Integer).void }
      def render_state_machine_button(ret, m_id)
        case ret.status
        when "requested"
          form(action: update_status_returns_dashboard_path(ret.id, merchant_id: m_id, status: "picked_up_from_buyer"), method: "post", class: "w-full") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render Components::UI::Button.new(variant: "primary", type: "submit", custom_class: "w-full") { "🚚 Mark Picked Up from Buyer" }
          end
        when "picked_up_from_buyer"
          form(action: update_status_returns_dashboard_path(ret.id, merchant_id: m_id, status: "received_at_warehouse"), method: "post", class: "w-full") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render Components::UI::Button.new(variant: "secondary", type: "submit", custom_class: "w-full") { "🏬 Receive at Warehouse" }
          end
        when "received_at_warehouse"
          form(action: update_status_returns_dashboard_path(ret.id, merchant_id: m_id, status: "inspected"), method: "post", class: "w-full") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render Components::UI::Button.new(variant: "primary", type: "submit", custom_class: "w-full bg-emerald-600 hover:bg-emerald-500") { "🔍 Pass QA & Inspect" }
          end
        when "inspected"
          form(action: update_status_returns_dashboard_path(ret.id, merchant_id: m_id, status: "resolved"), method: "post", class: "w-full") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render Components::UI::Button.new(variant: "primary", type: "submit", custom_class: "w-full bg-emerald-600 hover:bg-emerald-500") { "✅ Resolve & Issue Exchange" }
          end
        else
          res_at = ret.resolved_at
          resolved_date = res_at ? res_at.strftime("%d %b %Y %H:%M") : "Today"
          div(class: "text-center text-xs font-semibold text-emerald-400 py-2 bg-emerald-500/10 rounded-lg border border-emerald-500/20") do
            "✅ Return Resolved on #{resolved_date}"
          end
        end
      end
    end
  end
end
