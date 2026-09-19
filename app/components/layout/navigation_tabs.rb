# typed: strict
# frozen_string_literal: true

module Components
  module Layout
    class NavigationTabs < Components::Base
      extend T::Sig

      sig do
        params(
          current_merchant: T.nilable(Merchant),
          current_path: String
        ).void
      end
      def initialize(current_merchant:, current_path:)
        @current_merchant = T.let(current_merchant, T.nilable(Merchant))
        @current_path = T.let(current_path, String)
      end

      sig { void }
      def view_template
        m_id = @current_merchant ? @current_merchant.id : 1

        tabs = [
          { name: "📦 Warehouse Order Queue", path: orders_path(merchant_id: m_id) },
          { name: "🔄 Returns & Exchange Hub", path: returns_dashboard_path(merchant_id: m_id) },
          { name: "📊 SLA Analytics", path: analytics_dashboard_path(merchant_id: m_id) },
          { name: "📄 Driver Manifests", path: manifests_dashboard_path(merchant_id: m_id) },
          { name: "⚙️ Settings & API", path: settings_path(merchant_id: m_id) },
          { name: "📱 PDA Scanner Mode", path: scanner_path(merchant_id: m_id) },
          { name: "🆘 Support & Health", path: support_path(merchant_id: m_id) }
        ]

        div(class: "flex flex-wrap gap-3 mb-6 px-6") do
          tabs.each do |tab|
            is_active = @current_path == tab[:path] || @current_path.start_with?(tab[:path].split("?").first.to_s)
            pill_class = if is_active
              "px-4 py-2 text-xs font-semibold rounded-xl bg-indigo-600 text-white shadow-lg shadow-indigo-500/25 border border-indigo-500/50 transition-all duration-200"
            else
              "px-4 py-2 text-xs font-medium rounded-xl bg-slate-800/80 text-slate-300 hover:bg-slate-700/80 border border-slate-700/50 transition-all duration-200"
            end

            a(href: tab[:path], class: pill_class) do
              tab[:name]
            end
          end
        end
      end
    end
  end
end
