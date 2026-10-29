# typed: strict

module Api
  module V1
    class BinsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStaffAuthorization
      include ApiAdminAudit
      include ApiStringParams
      include ApiLedgerQuery

      SHELF_LEVELS = T.let(0..Kinetix::IntegerParam::MAX_INT32, T::Range[Integer])

      sig { void }
      def index
        return unless require_staff!

        page = ledger.bins(after: query_text(:after, WarehouseBin::MAX_CODE_LENGTH), limit: page_limit)
        render(json: { bins: page.items.map(&:serialize), next_after: page.last_shown&.bin_code })
      end

      sig { void }
      def create
        return unless require_staff!

        action = Kinetix::Metrics::AdminActions::BIN_UPSERT
        audit_admin_action(action, target_keys: %i[bin_code]) { upsert }
      end

      private

      sig { void }
      def upsert
        return if refuse_unusable_strings(%i[bin_code zone], coded: false)

        raw_level = params[:shelf_level]
        given = !(raw_level.nil? || raw_level == "")
        shelf_level = given ? Kinetix::IntegerParam.parse(raw_level, signed: false) : nil
        if given && !(shelf_level && SHELF_LEVELS.cover?(shelf_level))
          render(
            json: {
              error: "shelf_level must be a whole number from 0 to #{SHELF_LEVELS.end}, written in digits"
            },
            status: :unprocessable_content
          )
          return
        end

        result = Inventory::UpsertBinService.new(
          bin_code: string_param(:bin_code).to_s,
          zone: string_param(:zone).presence,
          shelf_level: shelf_level
        ).call

        if result.errors.any?
          render(json: { error: result.errors.join(", ") }, status: :unprocessable_content)
          return
        end

        bin = result.bin
        render(
          json: {
            id: bin.id,
            bin_code: bin.bin_code,
            zone: bin.zone,
            shelf_level: bin.shelf_level
          },
          status: result.created ? :created : :ok
        )
      end
    end
  end
end
