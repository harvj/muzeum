module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :session_id

    def connect
      session = Session.unexpired.includes(:user).find_by(id: cookies.signed[:session_id])
      unless session&.user&.login_enabled? && session.last_seen_at&.after?(12.hours.ago) && session.verified_at&.after?(60.seconds.ago)
        reject_unauthorized_connection
      end
      self.session_id = session.id
    end
  end
end
