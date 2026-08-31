# typed: strict

class SessionsController < ApplicationController
  extend T::Sig

  sig { void }
  def new
    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchants = Merchant.order(:name).to_a
    @merchants = T.let(merchants, T.nilable(T::Array[Merchant]))
    render layout: false
  end

  sig { void }
  def create
    email = params[:email].to_s.strip
    password_input = params[:password].to_s

    if email.blank? || password_input.blank?
      flash[:alert] = "⚠️ Email and password are required."
      redirect_to login_path and return
    end

    staff = begin
      StaffUser.find_by(email: email)
    rescue StandardError
      nil
    end

    unless staff && T.unsafe(staff).authenticate(password_input)
      flash[:alert] = "⚠️ Invalid email or password."
      redirect_to login_path and return
    end

    valid_staff = T.must(staff)
    merchant_id = valid_staff.merchant_id
    merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
    merchant = merchant_repo.find_by_id(merchant_id)

    if merchant.nil?
      flash[:alert] = "⚠️ Associated Merchant record not found!"
      redirect_to login_path and return
    end

    valid_merchant = T.must(merchant)

    reset_session
    session[:merchant_id] = merchant_id
    session[:staff_id] = valid_staff.id
    session[:role] = valid_staff.role

    flash[:notice] = "🔓 Welcome to #{valid_merchant.name}, #{valid_staff.name}."
    redirect_to orders_path(merchant_id: merchant_id)
  end

  sig { void }
  def destroy
    session[:merchant_id] = nil
    session[:staff_id] = nil
    session[:role] = nil

    flash[:notice] = "🔒 Logged out successfully."
    redirect_to login_path
  end
end
