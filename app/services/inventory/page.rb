# typed: strict

module Inventory
  class Page
    extend T::Sig
    extend T::Generic

    Item = type_member

    sig { returns(T::Array[Item]) }
    attr_reader :items

    sig { returns(T::Boolean) }
    attr_reader :more

    sig { params(fetched: T::Array[Item], limit: Integer).void }
    def initialize(fetched, limit)
      @items = T.let(fetched.first(limit), T::Array[Item])
      @more = T.let(fetched.length > limit, T::Boolean)
    end

    sig { returns(T.nilable(Item)) }
    def last_shown
      more ? items.last : nil
    end
  end
end
