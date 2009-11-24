# Settings specified here will take precedence over those in config/environment.rb

# In the development environment your application's code is reloaded on
# every request.  This slows down response time but is perfect for development
# since you don't have to restart the webserver when you make code changes.
config.cache_classes = false

# Log error messages when you accidentally call methods on nil.
config.whiny_nils = true

# Show full error reports and disable caching
config.action_controller.consider_all_requests_local = true
config.action_view.debug_rjs                         = true
config.action_controller.perform_caching             = false
SslRequirement.disable_ssl_check = true

# use_gateway = false
use_gateway = true

ActiveMerchant::Billing::Base.mode = :test

config.to_prepare do
  if use_gateway && APP_CONFIG[:gateway].is_a?(Hash)
    Purchase.gateway = ActiveMerchant::Billing::AuthorizeNetGateway.new({
      :login    => APP_CONFIG[:gateway][:login],
      :password => APP_CONFIG[:gateway][:password],
      :test => true
    })
  else
    Purchase.gateway = ActiveMerchant::Billing::BogusGateway.new
  end
end

PAYPAL_POST_URL = "https://www.sandbox.paypal.com/cgi-bin/webscr"
PAYPAL_EMAIL = "info+s_1240233800_per@spot.us"

config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = false
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  :enable_starttls_auto => false,
  :address        => "localhost",
  :port           => 2525,
  :domain         => "periodismoalacarta.com"
}
