# spec/requests/sessions_spec.rb
require "rails_helper"

RSpec.describe "Authentication Sessions", type: :request do
  let!(:merchant) { Merchant.create!(code: "BH-001", name: "Boutique Hijab Premium", api_key: "luxe_prod_sec_key_123", cutoff_hour: 14) }

  let!(:staff) do
    StaffUser.create!(
      merchant: merchant,
      name: "Budi Hendra",
      email: "budi@boutiquehijab.id",
      role: "Warehouse Manager",
      password: "secret123"
    )
  end

  describe "GET /login" do
    it "renders the glassmorphic login page successfully" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("LUXE OMS")
      expect(response.body).to include("SIGN IN TO CONTROL CENTER")
    end
  end

  describe "POST /login" do
    context "with valid credentials" do
      it "authenticates staff user, sets the session, and redirects to the orders dashboard" do
        post login_path, params: { email: "budi@boutiquehijab.id", password: "secret123" }

        expect(response).to redirect_to(orders_path(merchant_id: merchant.id))
        expect(session[:merchant_id]).to eq(merchant.id)
        expect(session[:staff_id]).to eq(staff.id)
        expect(session[:role]).to eq("Warehouse Manager")
        expect(flash[:notice]).to include("Welcome to Boutique Hijab Premium")
      end
    end

    context "with invalid password" do
      it "rejects authentication and redirects back to login with alert" do
        post login_path, params: { email: "budi@boutiquehijab.id", password: "wrong_password" }

        expect(response).to redirect_to(login_path)
        expect(session[:merchant_id]).to be_nil
        expect(session[:staff_id]).to be_nil
        follow_redirect!
        expect(response.body).to include("Invalid email or password")
      end
    end

    context "with non-existent email" do
      it "rejects login and redirects to login path" do
        post login_path, params: { email: "unknown@boutiquehijab.id", password: "secret123" }

        expect(response).to redirect_to(login_path)
        follow_redirect!
        expect(response.body).to include("Invalid email or password")
      end
    end

    # Regression guards for the two auth bypasses removed in S1 / P0-WH-01.
    context "when the merchant API key is submitted as the password" do
      it "refuses to open a session for a staff account" do
        post login_path, params: { email: "budi@boutiquehijab.id", password: merchant.api_key }

        expect(response).to redirect_to(login_path)
        expect(session[:merchant_id]).to be_nil
        expect(session[:staff_id]).to be_nil
        follow_redirect!
        expect(response.body).to include("Invalid email or password")
      end

      it "refuses to open a session when the email belongs to no staff account" do
        post login_path, params: { email: "attacker@example.com", password: merchant.api_key }

        expect(response).to redirect_to(login_path)
        expect(session[:merchant_id]).to be_nil
        expect(session[:staff_id]).to be_nil
        expect(session[:role]).to be_nil
      end
    end

    context "message parity" do
      it "returns a byte-identical alert for an unknown email and for a wrong password" do
        post login_path, params: { email: "unknown@boutiquehijab.id", password: "secret123" }
        unknown_email_alert = flash[:alert]

        post login_path, params: { email: "budi@boutiquehijab.id", password: "wrong_password" }
        wrong_password_alert = flash[:alert]

        expect(unknown_email_alert).to eq(wrong_password_alert)
        expect(unknown_email_alert).to include("Invalid email or password")
        expect(unknown_email_alert).not_to include("budi@boutiquehijab.id")
        expect(wrong_password_alert).not_to include("Budi Hendra")
      end
    end
  end

  describe "DELETE /logout" do
    it "clears session and redirects to login" do
      post login_path, params: { email: "budi@boutiquehijab.id", password: "secret123" }
      expect(session[:staff_id]).to eq(staff.id)

      delete logout_path
      expect(response).to redirect_to(login_path)
      expect(session[:merchant_id]).to be_nil
      expect(session[:staff_id]).to be_nil
    end
  end

  describe "ApplicationController Authentication Guard" do
    it "redirects unauthenticated access to /orders back to /login" do
      delete logout_path
      get orders_path

      expect(response).to redirect_to(login_path)
    end
  end
end
