require "rails_helper"

RSpec.describe "Phlex UI Components", type: :component do
  describe Components::UI::Badge do
    it "renders received badge with correct CSS classes" do
      badge = Components::UI::Badge.new(status: "received")
      html = badge.call
      expect(html).to include("RECEIVED")
      expect(html).to include("bg-blue-500/10")
    end

    it "renders delivered badge with emerald CSS classes" do
      badge = Components::UI::Badge.new(status: "delivered")
      html = badge.call
      expect(html).to include("DELIVERED")
      expect(html).to include("bg-emerald-500/10")
    end
  end

  describe Components::UI::Button do
    it "renders primary button with text" do
      button = Components::UI::Button.new(variant: "primary")
      html = button.call { "Click Me" }
      expect(html).to include("Click Me")
      expect(html).to include("bg-indigo-600")
    end
  end

  describe Components::UI::Card do
    it "renders card with title and subtitle" do
      card = Components::UI::Card.new(title: "Order Overview", subtitle: "Live Status")
      html = card.call { "Card Body Content" }
      expect(html).to include("Order Overview")
      expect(html).to include("Live Status")
      expect(html).to include("Card Body Content")
    end
  end
end
