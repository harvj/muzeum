class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Please try again later." }

  def new
  end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    # Run bcrypt even for unknown addresses to avoid an obvious fast failure path.
    password_valid = (user || User.new(password_digest: dummy_digest)).authenticate(params[:password].to_s)
    if password_valid && user&.login_enabled?
      start_session(user)
      redirect_to root_path, status: :see_other
    else
      redirect_to new_session_path, alert: "Email or password is incorrect.", status: :see_other
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

  def dummy_digest
    # Fixed valid bcrypt digest: no account or reusable credential is created.
    "$2a$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW"
  end
end
