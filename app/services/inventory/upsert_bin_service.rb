# typed: strict
# frozen_string_literal: true

module Inventory
  class UpsertBinService
    extend T::Sig

    class Result < T::Struct
      const :bin, WarehouseBin
      const :created, T::Boolean
      const :errors, T::Array[String]
    end

    sig { params(bin_code: String, zone: T.nilable(String), shelf_level: T.nilable(Integer)).void }
    def initialize(bin_code:, zone:, shelf_level:)
      @bin_code = bin_code
      @zone = zone
      @shelf_level = shelf_level
    end

    sig { returns(Result) }
    def call
      attempt(after_race: false)
    end

    private

    sig { params(after_race: T::Boolean).returns(Result) }
    def attempt(after_race:)
      bin = WarehouseBin.find_or_initialize_by(bin_code: @bin_code)
      creating = bin.new_record?
      bin.zone = @zone unless @zone.nil?
      bin.shelf_level = @shelf_level unless @shelf_level.nil?

      saved = bin.save
      return attempt(after_race: true) if !saved && !after_race && creating && lost_race?(bin)

      Result.new(bin: bin, created: saved && creating, errors: bin.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      raise if after_race

      attempt(after_race: true)
    end

    sig { params(bin: WarehouseBin).returns(T::Boolean) }
    def lost_race?(bin)
      bin.errors.of_kind?(:bin_code, :taken)
    end
  end
end
