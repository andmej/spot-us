# -*- coding: utf-8 -*-
class Mailer < ActionMailer::Base
  include ActionController::UrlWriter
  default_url_options[:host] = DEFAULT_HOST

  def activation_email(user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Bienvenido a Periodismo a la Carta – Por favor, verifica tu email"
    body :user => user
  end

  def citizen_signup_notification(user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Bienvenido a Periodismo a la Carta – Las noticias que tú quieras conocer"
    body :user => user
  end

  def reporter_signup_notification(user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Bienvenido a Periodismo a la Carta – Periodismo de investigación participativo"
    body :user => user
  end

  def organization_signup_notification(user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Important Información para participar"
    body :user => user
  end

  def news_org_signup_request(user)
    recipients '"Adrián Latorre" <adrian@periodismoalacarta.com>'
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Organización de noticias quiere participar"
    body        :user => user
  end

  def password_reset_notification(user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Recuperación de contraseña"
    body       :user => user
  end

  def pitch_created_notification(pitch)
    recipients '"Adrián Latorre" <adrian@periodismoalacarta.com>'
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: A pitch needs approval!"
    body       :pitch => pitch
  end

  def pitch_approved_notification(pitch)
    recipients pitch.user.email
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Your pitch has been approved!"
    body       :pitch => pitch
  end

  def pitch_accepted_notification(pitch)
    recipients '"Adrián Latorre" <adrian@periodismoalacarta.com>'
    bcc pitch.supporters.map(&:email).concat(Admin.all.map(&:email)).join(', ')
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Success!! Your Story is Funded!"
    body       :pitch => pitch
  end

  def admin_reporting_team_notification(pitch)
    recipients '"Adrián Latorre" <adrian@periodismoalacarta.com>'
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Someone wants to join a pitch's reporting team!"
    body       :pitch => pitch
  end

  def reporter_reporting_team_notification(pitch)
    recipients pitch.user.email
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Someone wants to join your reporting team!"
    body       :pitch => pitch
  end

  def approved_reporting_team_notification(pitch, user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Welcome to the reporting team!"
    body       :pitch => pitch
  end

  def applied_reporting_team_notification(pitch, user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: We received your application!"
    body       :pitch => pitch
  end

  def story_ready_notification(story)
    recipients '"Adrián Latorre" <adrian@periodismoalacarta.com>'
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Story ready for publishing"
    body       :story => story
  end

  def organization_approved_notification(user)
    recipients user.email
    from       MAIL_FROM_INFO
    subject    "Periodismo a la Carta: Important información on Joining"
    body       :user => user
  end

  def user_thank_you_for_donating(donation)
    recipients  donation.user.email
    from        MAIL_FROM_INFO
    subject     "Periodismo a la Carta: Gracias por ayudar con tu financiación!"
    body        :donation => donation
  end
end
