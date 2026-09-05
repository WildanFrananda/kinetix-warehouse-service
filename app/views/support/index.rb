# typed: strict
# frozen_string_literal: true

module Views
  module Support
    class Index < Views::Base
      extend T::Sig

      sig do
        params(
          action_cable_healthy: T::Boolean,
          phoenix_healthy: T::Boolean,
          phoenix_ping_ms: Integer,
          db_healthy: T::Boolean,
          base_url: String,
          current_merchant: T.nilable(Merchant),
          merchants: T.nilable(T::Array[Merchant]),
          notice_flash: T.nilable(String),
          alert_flash: T.nilable(String)
        ).void
      end
      def initialize(action_cable_healthy:, phoenix_healthy:, phoenix_ping_ms:, db_healthy:, base_url:, current_merchant:, merchants:, notice_flash: nil, alert_flash: nil)
        @action_cable_healthy = T.let(action_cable_healthy, T::Boolean)
        @phoenix_healthy = T.let(phoenix_healthy, T::Boolean)
        @phoenix_ping_ms = T.let(phoenix_ping_ms, Integer)
        @db_healthy = T.let(db_healthy, T::Boolean)
        @base_url = T.let(base_url, String)
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @merchants = T.let(merchants || [], T::Array[Merchant])
        @notice_flash = T.let(notice_flash, T.nilable(String))
        @alert_flash = T.let(alert_flash, T.nilable(String))
      end

      sig { void }
      def view_template
        m_id = @current_merchant ? @current_merchant.id : 1

        render Views::Layouts::ApplicationLayout.new(
          title: "Support & Operations Help Center | Fashion Fulfillment OMS",
          current_merchant: @current_merchant,
          merchants: @merchants,
          current_path: support_path
        ) do
          render_flash_banners

          div(class: "mb-8") do
            h1(class: "text-3xl font-bold text-white font-sans tracking-tight mb-2") { "Warehouse Operations & Integration Help Center" }
            p(class: "text-sm text-slate-400 font-sans max-w-4xl") do
              "Access critical standard operating procedures, technical documentation, and real-time system diagnostics to maintain operational velocity for "
              strong(class: "text-white") { @current_merchant ? @current_merchant.name : "Merchant" }
              "."
            end
          end

          # Critical Resources Grid
          div(class: "mb-8") do
            div(class: "text-xs font-bold text-slate-400 uppercase tracking-wider mb-4") { "⬍ CRITICAL RESOURCES" }
            div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
              render_resource_card("📖", "Warehouse SLA SOP Guide", "Standard operating procedures for maintaining Service Level Agreement compliance during peak shifts.", "sop-modal")
              render_resource_card("💠", "FleetPulse Elixir API Docs", "Technical documentation for integrating with the FleetPulse WebSocket cluster and dispatch API.", "api-modal")
              render_resource_card("⚠️", "Emergency Protocol SOP", "Immediate action workflows for system outages, hardware failures, and manual override procedures.", "emergency-modal", border_color: "border-rose-500/40")
            end
          end

          # Health & Escalation Grid
          div(class: "grid grid-cols-1 lg:grid-cols-[380px_1fr] gap-6") do
            render_system_health_card
            render_escalation_card(m_id)
          end

          # Modals
          render_modals(m_id)
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

      sig { params(icon: String, title: String, desc: String, modal_id: String, border_color: String).void }
      def render_resource_card(icon, title, desc, modal_id, border_color: "border-slate-800")
        render Components::UI::Card.new(custom_class: "cursor-pointer hover:border-indigo-500/50 transition-all duration-200 #{border_color}") do
          div(data_toggle: modal_id) do
            div(class: "flex items-center justify-between mb-4") do
              div(class: "w-10 h-10 rounded-lg bg-slate-800 border border-slate-700 flex items-center justify-center text-lg") { icon }
              span(class: "text-slate-400 text-lg font-bold") { "→" }
            end
            h3(class: "text-base font-bold text-white mb-1 font-sans") { title }
            p(class: "text-xs text-slate-400 leading-relaxed") { desc }
          end
        end
      end

      sig { void }
      def render_system_health_card
        render Components::UI::Card.new do
          div(class: "text-xs font-bold text-slate-400 uppercase tracking-wider mb-4") { "🗄️ LIVE SYSTEM HEALTH" }

          div(class: "space-y-3 font-sans text-xs") do
            div(class: "p-3 rounded-lg bg-slate-950 border border-slate-800/80 flex items-center justify-between") do
              span(class: "font-semibold text-white") { "~ Action Cable Stream" }
              if @action_cable_healthy
                span(class: "text-emerald-400 font-bold") { "Connected 🟢" }
              else
                span(class: "text-rose-400 font-bold") { "Disconnected 🔴" }
              end
            end

            div(class: "p-3 rounded-lg bg-slate-950 border border-slate-800/80 flex items-center justify-between") do
              span(class: "font-semibold text-white") { "⌁ Phoenix WebSocket" }
              if @phoenix_healthy
                span(class: "text-emerald-400 font-bold font-mono") { "#{@phoenix_ping_ms}ms Ping 🟢" }
              else
                span(class: "text-rose-400 font-bold") { "Offline 🔴" }
              end
            end

            div(class: "p-3 rounded-lg bg-slate-950 border border-slate-800/80 flex items-center justify-between") do
              span(class: "font-semibold text-white") { "🗄️ PostgreSQL Database" }
              if @db_healthy
                span(class: "text-emerald-400 font-bold") { "Healthy 🟢" }
              else
                span(class: "text-rose-400 font-bold") { "Offline 🔴" }
              end
            end
          end
        end
      end

      sig { params(m_id: Integer).void }
      def render_escalation_card(m_id)
        merchant_name = @current_merchant ? @current_merchant.name : "Merchant"

        render Components::UI::Card.new(custom_class: "flex flex-col justify-between h-full") do
          div do
            h2(class: "text-xl font-bold text-white mb-2 font-sans") { "Need Human Intervention?" }
            p(class: "text-xs text-slate-400 leading-relaxed max-w-xl mb-6") do
              "Escalate complex logistics anomalies or technical faults directly to the Level 3 Command Center for "
              strong(class: "text-white") { merchant_name }
              "."
            end
          end

          div(class: "flex items-center gap-4 flex-wrap") do
            render Components::UI::Button.new(variant: "primary", data_toggle: "ticket-modal") { "🎫 Open Support Ticket" }

            form(action: start_chat_support_path(merchant_id: m_id), method: "post", class: "inline-block") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              render Components::UI::Button.new(variant: "secondary") { "💬 Start Live Chat" }
            end
          end
        end
      end

      sig { params(m_id: Integer).void }
      def render_modals(m_id)
        cutoff = @current_merchant ? @current_merchant.cutoff_hour : 14

        # SOP Modal
        render_modal_container("sop-modal", "📖 Warehouse SLA SOP Guide") do
          p(class: "mb-2") do
            strong(class: "text-white") { "1. Cutoff Triage: " }
            "Orders received before #{sprintf('%02d', cutoff)}:00 WIB must be picked & packed within 60 minutes."
          end
          p do
            strong(class: "text-white") { "2. Barcode Scanning: " }
            "Every item SKU & resi barcode must be scanned via thermal label before handing over to courier."
          end
        end

        # API Docs Modal
        render_modal_container("api-modal", "💠 FleetPulse Elixir API Docs") do
          p(class: "mb-2") do
            strong(class: "text-white") { "Endpoint: " }
            code(class: "text-indigo-400 font-mono") { "#{@base_url}/api/v1/orders" }
          end
          p do
            strong(class: "text-white") { "Auth Header: " }
            code(class: "text-indigo-400 font-mono") { "Authorization: Bearer <access token>" }
          end
        end

        # Emergency Modal
        render_modal_container("emergency-modal", "⚠️ Emergency Protocol SOP") do
          p(class: "mb-2") do
            strong(class: "text-white") { "1. Emergency Halt: " }
            "Click 'Emergency Halt' in top header bar to pause automated driver assignments."
          end
          p do
            strong(class: "text-white") { "2. Manual Escalation: " }
            "Contact Level 3 Command Center via Live Chat immediately."
          end
        end

        # Ticket Modal
        div(id: "ticket-modal", class: "modal-overlay hidden fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md") do
          div(class: "modal-card w-full max-w-lg bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-2xl") do
            div(class: "flex items-center justify-between mb-4 pb-3 border-b border-slate-800") do
              h3(class: "text-lg font-bold text-white font-sans") { "🎫 Escalate Support Ticket" }
              button(type: "button", class: "text-slate-400 hover:text-white text-xl font-bold", data_close: "ticket-modal") { "×" }
            end

            form(action: create_ticket_support_path(merchant_id: m_id), method: "post", class: "space-y-4") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div do
                label(class: "block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-1") { "Ticket Subject / Anomaly Title" }
                input(type: "text", name: "subject", placeholder: "e.g. Courier Dispatch Delay / Picking Discrepancy", required: true, class: "w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-indigo-500")
              end

              div(class: "flex items-center justify-end gap-3 pt-4 border-t border-slate-800") do
                button(type: "button", class: "px-4 py-2 text-xs font-semibold text-slate-400 hover:text-white border border-slate-800 rounded-lg", data_close: "ticket-modal") { "Cancel" }
                render Components::UI::Button.new(variant: "primary", type: "submit") { "Submit Ticket Escalation" }
              end
            end
          end
        end
      end

      sig { params(modal_id: String, title: String, block: T.proc.void).void }
      def render_modal_container(modal_id, title, &block)
        div(id: modal_id, class: "modal-overlay hidden fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md") do
          div(class: "modal-card w-full max-w-lg bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-2xl") do
            div(class: "flex items-center justify-between mb-4 pb-3 border-b border-slate-800") do
              h3(class: "text-lg font-bold text-white font-sans") { title }
              button(type: "button", class: "text-slate-400 hover:text-white text-xl font-bold", data_close: modal_id) { "×" }
            end

            div(class: "text-xs text-slate-300 leading-relaxed font-sans") do
              yield
            end

            div(class: "mt-6 text-right pt-3 border-t border-slate-800") do
              button(type: "button", class: "px-4 py-2 text-xs font-semibold text-slate-400 hover:text-white border border-slate-800 rounded-lg", data_close: modal_id) { "Close" }
            end
          end
        end
      end
    end
  end
end
