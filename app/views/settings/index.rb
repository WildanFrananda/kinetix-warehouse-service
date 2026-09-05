# typed: strict
# frozen_string_literal: true

module Views
  module Settings
    class Index < Views::Base
      extend T::Sig

      sig do
        params(
          current_merchant: T.nilable(Merchant),
          merchants: T.nilable(T::Array[Merchant]),
          base_url: String,
          notice_flash: T.nilable(String),
          alert_flash: T.nilable(String)
        ).void
      end
      def initialize(current_merchant:, merchants:, base_url:, notice_flash: nil, alert_flash: nil)
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @merchants = T.let(merchants || [], T::Array[Merchant])
        @base_url = T.let(base_url, String)
        @notice_flash = T.let(notice_flash, T.nilable(String))
        @alert_flash = T.let(alert_flash, T.nilable(String))
      end

      sig { void }
      def view_template
        m_id = @current_merchant ? @current_merchant.id : 1

        render Views::Layouts::ApplicationLayout.new(
          title: "Settings & API Configuration | Fashion Fulfillment OMS",
          current_merchant: @current_merchant,
          merchants: @merchants,
          current_path: settings_path
        ) do
          render_flash_banners

          div(class: "mb-8") do
            h1(class: "text-3xl font-bold text-white font-sans tracking-tight mb-2") { "Settings & Merchant Logistics Configuration" }
            p(class: "text-sm text-slate-400 font-sans") do
              "Manage your API credentials, SLA cutoffs, and Webhook integrations for the enterprise logistics network."
            end
          end

          # Settings Grid Layout
          div(class: "grid grid-cols-1 lg:grid-cols-[1.5fr_1fr] gap-8") do
            # Left Column
            div(class: "flex flex-col gap-6") do
              render_endpoints_card(m_id)
            end

            # Right Column
            render_sla_cutoff_card(m_id)
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


      sig { params(m_id: Integer).void }
      def render_endpoints_card(m_id)
        rest_endpoint = "#{@base_url}/api/v1/orders"
        ws_endpoint = "#{@base_url.sub(/^http/, 'ws')}/cable"

        render Components::UI::Card.new do
          div(class: "flex items-center justify-between mb-2") do
            div(class: "flex items-center gap-3") do
              span(class: "text-xl") { "📡" }
              h3(class: "text-lg font-bold text-white font-sans") { "Integration Endpoints" }
            end

            form(action: test_ping_settings_path(merchant_id: m_id), method: "post", class: "inline-block") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              render Components::UI::Button.new(variant: "secondary", type: "submit", custom_class: "text-xs py-1.5") { "⚡ Test Ping Latency" }
            end
          end

          p(class: "text-xs text-slate-400 mb-4") do
            "Configure your network egress to allow traffic to these regional endpoints."
          end

          div(class: "space-y-3 font-mono text-xs") do
            div(class: "p-3 rounded-lg bg-slate-950 border border-slate-800") do
              div(class: "flex items-center justify-between mb-1") do
                span(class: "text-slate-400 font-bold") { "REST API (v1)" }
                span(class: "text-emerald-400 font-bold text-[11px]") { "🟢 Operational" }
              end
              div(class: "text-white font-medium truncate") { rest_endpoint }
            end

            div(class: "p-3 rounded-lg bg-slate-950 border border-slate-800") do
              div(class: "flex items-center justify-between mb-1") do
                span(class: "text-slate-400 font-bold") { "FLEETPULSE WEBSOCKET" }
                span(class: "text-emerald-400 font-bold text-[11px]") { "🟢 Operational" }
              end
              div(class: "text-white font-medium truncate") { ws_endpoint }
            end
          end
        end
      end

      sig { params(m_id: Integer).void }
      def render_sla_cutoff_card(m_id)
        current_cutoff = @current_merchant ? @current_merchant.cutoff_hour : 15

        render Components::UI::Card.new(custom_class: "flex flex-col justify-between h-full") do
          div do
            div(class: "flex items-center gap-3 mb-6") do
              span(class: "text-xl") { "⏱️" }
              h3(class: "text-lg font-bold text-white font-sans") { "SLA Cutoff Rules" }
            end

            form(action: update_cutoff_settings_path(merchant_id: m_id), method: "post", class: "space-y-4 mb-6") do
              input(type: "hidden", name: "_method", value: "patch")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div do
                label(class: "block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2") do
                  "Same-Day Dispatch Cutoff"
                end

                select(
                  name: "cutoff_hour",
                  class: "w-full bg-slate-950 border border-slate-800 rounded-lg px-4 py-2.5 text-sm text-white font-mono font-bold focus:outline-none focus:ring-2 focus:ring-indigo-500"
                ) do
                  (8..22).each do |h|
                    option_text = "#{sprintf('%02d', h)}:00 WIB"
                    if current_cutoff == h
                      option(value: h.to_s, selected: true) { option_text }
                    else
                      option(value: h.to_s) { option_text }
                    end
                  end
                end
              end

              p(class: "text-xs text-slate-400 leading-relaxed") do
                "Orders placed after this cutoff hour roll over to the next business day dispatch queue."
              end

              render Components::UI::Button.new(variant: "primary", type: "submit", custom_class: "w-full") { "Update Cutoff Hour" }
            end
          end

          div(class: "p-4 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-xs text-slate-300 leading-relaxed flex items-start gap-3") do
            span(class: "text-lg") { "💡" }
            div { "Modifying cutoff times may affect your contracted merchant SLA guarantees. Proceed with caution." }
          end
        end
      end
    end
  end
end
