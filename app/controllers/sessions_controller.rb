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
    password_input = params[:password_or_api_key].to_s

    if email.blank? || password_input.blank?
      flash[:alert] = "⚠️ Email and Password are required!"
      redirect_to login_path and return
    end

    staff = begin
      StaffUser.find_by(email: email)
    rescue StandardError
      nil
    end

    identity_client = Identity::GrpcClient.new
    merchant_info = identity_client.get_merchant_by_api_key(api_key: password_input)

    if merchant_info
      m_id = merchant_info[:user_id].to_i
      session[:merchant_id] = m_id
      session[:staff_id] = staff&.id
      session[:role] = staff&.role || "Warehouse Staff"
      flash[:notice] = "🔓 Authentication Successful via gRPC IdentityService! Welcome back, #{email}."
      redirect_to orders_path(merchant_id: m_id)
      return
    end

    if staff
      valid_staff = staff
      merchant_id = valid_staff.merchant_id
      merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
      merchant = merchant_repo.find_by_id(merchant_id)

      if merchant.nil?
        flash[:alert] = "⚠️ Associated Merchant record not found!"
        redirect_to login_path and return
      end

      valid_merchant = T.must(merchant)
      password_valid = T.unsafe(valid_staff).authenticate(password_input) || (password_input == valid_merchant.api_key)

      unless password_valid
        flash[:alert] = "⚠️ Invalid Password for #{valid_staff.name}!"
        redirect_to login_path and return
      end

      session[:merchant_id] = merchant_id
      session[:staff_id] = valid_staff.id
      session[:role] = valid_staff.role

      flash[:notice] = "🔓 Authentication Successful! Welcome to #{valid_merchant.name}, #{valid_staff.name}."
      redirect_to orders_path(merchant_id: merchant_id)
      return
    end

    flash[:alert] = "No registered staff account found for '#{email}'!"
    redirect_to login_path
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
