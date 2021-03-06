# == Schema Information
# Schema version: 20090218144012
#
# Table name: users
#
#  id                        :integer(4)      not null, primary key
#  email                     :string(255)
#  crypted_password          :string(40)
#  salt                      :string(40)
#  created_at                :datetime
#  updated_at                :datetime
#  remember_token            :string(255)
#  remember_token_expires_at :datetime
#  first_name                :string(255)
#  last_name                 :string(255)
#  type                      :string(255)
#  photo_file_name           :string(255)
#  photo_content_type        :string(255)
#  photo_file_size           :integer(4)
#  location                  :string(255)
#  about_you                 :text
#  website                   :string(255)
#  address1                  :string(255)
#  address2                  :string(255)
#  city                      :string(255)
#  state                     :string(255)
#  zip                       :string(255)
#  phone                     :string(255)
#  country                   :string(255)
#  notify_tips               :boolean(1)      not null
#  notify_pitches            :boolean(1)      not null
#  notify_stories            :boolean(1)      not null
#  notify_spotus_news        :boolean(1)      not null
#  fact_check_interest       :boolean(1)      not null
#  status                    :string(255)
#  organization_name         :string(255)
#  established_year          :string(255)
#  deleted_at                :datetime
#  activation_code           :string(255)
#

require 'digest/sha1'
require 'zlib'
class User < ActiveRecord::Base
  acts_as_paranoid
  include HasTopics
  include AASMWithFixes
  include NetworkMethods

  TYPES = ["Citizen", "Reporter", "Organization", "Admin"]
  CREATABLE_TYPES = TYPES - ["Admin"]

  aasm_column :status
  aasm_state :inactive
  aasm_state :active
  aasm_initial_state  :inactive
  aasm_event :activate do
    transitions :from => :inactive, :to => :active,
      :on_transition => lambda{ |user|
        user.send(:deliver_signup_notification)
        user.send(:clear_activation_code)
      }
    transitions :from => :approved, :to => :active,
      :on_transition => lambda{ |user|
        user.send(:clear_activation_code)
      }
  end

  belongs_to :category

  has_many :donations, :conditions => {:donation_type => "payment"} do
    def pitch_sum(pitch)
      self.paid.all(:conditions => {:pitch_id => pitch}).map(&:amount).sum
    end
  end
  
  has_many :credit_pitches, :class_name => "Donation", :conditions => {:donation_type => "credit"} do
    def pitch_sum(pitch)
      self.paid.all(:conditions => {:pitch_id => pitch}).map(&:amount).sum
    end
  end

  has_many :all_donations, :class_name => "Donation"

  has_many :spotus_donations
  has_many :tips
  has_many :pitches
  has_many :posts
  has_many :stories
  has_many :jobs
  has_many :samples
  has_many :credits

  has_many :comments
  has_many :contributor_applications
  has_many :pledges do
    def tip_sum(tip)
      self.all(:conditions => {:tip_id => tip}).map(&:amount).sum
    end
  end

  # Virtual attribute for the unencrypted password
  attr_accessor :password

  validates_presence_of     :email, :first_name, :last_name
  validates_presence_of     :password, :password_confirmation, :if => :should_validate_password?
  validates_length_of       :password, :within => 4..40,       :if => :should_validate_password?
  validates_confirmation_of :password,                         :if => :should_validate_password?
  validates_length_of       :email,    :within => 3..100
  validates_uniqueness_of   :email, :case_sensitive => false, :scope => :deleted_at
  validates_inclusion_of    :type, :in => User::TYPES
  validates_acceptance_of   :terms_of_service
  validates_format_of       :website, :with => %r{^http://}, :allow_blank => true

  before_validation_on_create :generate_activation_code
  before_save :encrypt_password, :unless => lambda {|user| user.password.blank? }
  after_create :register_user_to_fb

  has_attached_file :photo,
                    :styles      => { :thumb => '50x50#' },
                    :path        => ":rails_root/public/system/profiles/" <<
                                    ":attachment/:id_partition/" <<
                                    ":basename_:style.:extension",
                    :url         => "/system/profiles/:attachment/:id_partition/" <<
                                    ":basename_:style.:extension",
                    :default_url => "/images/default_avatar.png"

  # prevents a user from submitting a crafted form that bypasses activation
  # anything else you want your user to change should be added here.
  attr_accessible :about_you, :address1, :address2, :city, :country,
    :email, :fact_check_interest, :first_name, :last_name,
    :location, :notify_blog_posts, :notify_pitches, :notify_spotus_news, :notify_stories,
    :notify_tips, :password, :password_confirmation, :phone, :photo, :state,
    :terms_of_service, :topics_params, :website, :zip, :organization_name,
    :established_year, :network_id, :category_id
  named_scope :fact_checkers, :conditions => {:fact_check_interest => true}
  named_scope :approved_news_orgs, :conditions => {:status => 'approved'}
  named_scope :unapproved_news_orgs, :conditions => {:status => 'needs_approval'}

  def self.opt_in_defaults
    { :notify_blog_posts => true,
      :notify_tips => true,
      :notify_pitches => true,
      :notify_stories => true,
      :notify_spotus_news => true }
  end

  def self.new(options = nil, &block)
    options = (options || {}).stringify_keys
    options.merge!(opt_in_defaults)
    if User::CREATABLE_TYPES.include?(options["type"])
      returning compute_type(options["type"]).allocate do |model|
        model.send(:initialize, options, &block)
      end
    elsif options["type"].blank?
      super
    else
      raise ArgumentError, "invalid subclass of #{inspect}"
    end
  end
  
################### facebook ######################
  #find the user in the database, first by the facebook user id and if that fails through the email hash
  def self.find_by_fb_user(fb_user)
    User.find_by_fb_user_id(fb_user.uid) || User.find_by_email_hash(fb_user.email_hashes)
  end
  #Take the data returned from facebook and create a new user from it.
  #We don't get the email from Facebook and because a facebooker can only login through Connect we just generate a unique login name for them.
  #If you were using username to display to people you might want to get them to select one after registering through Facebook Connect
  def self.create_from_fb_connect(fb_user)
    new_facebooker = User.new(:name => fb_user.name, :login => "facebooker_#{fb_user.uid}", :password => "", :email => "", 
      :network_id => Network.first)
    new_facebooker.type = "Citizen"
    new_facebooker.status = "active"
    new_facebooker.fb_user_id = fb_user.uid.to_i
    #We need to save without validations
    new_facebooker.save(false)
    new_facebooker.register_user_to_fb
  end

  #We are going to connect this user object with a facebook id. But only ever one account.
  def link_fb_connect(fb_user_id)
    unless fb_user_id.nil?
      #check for existing account
      existing_fb_user = User.find_by_fb_user_id(fb_user_id)
      #unlink the existing account
      unless existing_fb_user.nil?
        existing_fb_user.fb_user_id = nil
        existing_fb_user.save(false)
      end
      #link the new one
      self.fb_user_id = fb_user_id
      save(false)
    end
  end

  #The Facebook registers user method is going to send the users email hash and our account id to Facebook
  #We need this so Facebook can find friends on our local application even if they have not connect through connect
  #We then use the email hash in the database to later identify a user from Facebook with a local user
  def register_user_to_fb
    users = {:email => email, :account_id => id}
    Facebooker::User.register([users])
    self.email_hash = Facebooker::User.hash_email(email)
    save(false)
  end
  
  def facebook_user?
    return !fb_user_id.nil? && fb_user_id > 0
  end

########### end facebook ##############

  def citizen?
    self.is_a? Citizen
  end

  def reporter?
    self.is_a? Reporter
  end

  def organization?
    self.is_a? Organization
  end

  def admin?
    self.is_a? Admin
  end

  def total_credits_in_cents
    (total_credits * 100).to_i
  end

  def total_credits
    self.credits.map(&:amount).sum.to_f
  end
  
  def remaining_credits
      total_credits - self.credit_pitches.unpaid.map(&:amount).sum.to_f
  end
  
  def allocated_credits
      self.credit_pitches.unpaid.map(&:amount).sum.to_f
  end
  
  def has_enough_credits?(credit_pitch_amounts)
      credit_total = 0
      credit_pitch_amounts.values.each do |val|
        credit_total += val["amount"].to_f
      end
      return true if credit_total <= self.total_credits
      return false
  end
  
  def apply_credit_pitches
      #refactor - there must be a nicer ruby-like way to do this
      
      transaction do 
        credit_pitch_ids = self.credit_pitches.unpaid.map{|credit_pitch| [credit_pitch.pitch.id]}.join(", ")
        credit = Credit.create(:user => self, :description => "Applied to Pitches (#{credit_pitch_ids})",
                        :amount => (0 - self.allocated_credits))
        self.credit_pitches.unpaid.each do |credit_pitch|
          credit_pitch.credit_id = credit.id
          credit_pitch.pay!
        end
      end 
  end

  def self.createable_by?(user)
    true
  end

  def credits?
    total_credits > 0
  end
  
  def current_balance
      unpaid_donations_sum - allocated_credits + current_spotus_donation.amount
  end
  
  # Authenticates a user by their email and unencrypted password.  Returns the user or nil.
  def self.authenticate(email, password)
    u = find_by_email(email) # need to get the salt
    return nil unless u && u.activated?
    u && u.authenticated?(password) ? u : nil
  end

  # Encrypts some data with the salt.
  def self.encrypt(password, salt)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end

  def self.generate_csv
    FasterCSV.generate do |csv|
      # header row
      csv << ["type", "email", "first_name", "last_name", "network",
              "notify_tips", "notify_pitches",  "notify_pitches",
              "notify_stories", "notify_spotus_news", "fact_check_interest"]

      # data rows
      User.all.each do |user|
        csv << [user.type, user.email, user.first_name, user.last_name,
                user.network.name, user.notify_blog_posts, user.notify_tips, user.notify_pitches,
                user.notify_stories, user.notify_spotus_news, user.fact_check_interest]
      end
    end
  end

  def editable_by?(user)
    (user == self)
  end

  def amount_pledged_to(tip)
    self.pledges.tip_sum(tip)
  end

  def amount_donated_to(pitch)
    self.donations.pitch_sum(pitch) + self.credit_pitches.pitch_sum(pitch)
  end

  # Encrypts the password with the user salt
  def encrypt(password)
    self.class.encrypt(password, salt)
  end

  def reset_password!
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a - %w(l o 0 1 i I L)
    string = (1..6).collect { chars[rand(chars.size)] }.join
    update_attributes(:password => string, :password_confirmation => string)
    Mailer.deliver_password_reset_notification(self)
  end

  def authenticated?(password)
    crypted_password == encrypt(password)
  end

  def remember_token?
    remember_token_expires_at && Time.now.utc < remember_token_expires_at
  end

  # These create and unset the fields required for remembering users between browser closes
  def remember_me
    remember_me_for 2.weeks
  end

  def remember_me_for(time)
    remember_me_until time.from_now.utc
  end

  def remember_me_until(time)
    self.remember_token_expires_at = time
    self.remember_token            = encrypt("#{email}--#{remember_token_expires_at}")
    save(false)
  end

  def forget_me
    self.remember_token_expires_at = nil
    self.remember_token            = nil
    save(false)
  end

  def activated?
    !activation_code?
  end

  def full_name
    [first_name, last_name].join(' ')
  end

  def has_donation_for?(pitch)
    donations.exists?(:pitch_id => pitch.id )
  end

  def has_donated_to?(pitch)
    donations.paid.exists?(:pitch_id => pitch.id)
  end

  def max_donation_for(pitch)
    pitch.max_donation_amount(self) - pitch.donations.total_amount_for_user(self)
  end

  def can_donate_to?(pitch)
    pitch.donations.total_amount_for_user(self) < pitch.max_donation_amount(self)
  end

  # TODO: remove after updating all models with amount
  def unpaid_donations_sum_in_cents
    donations.unpaid.empty? ? 0 : donations.unpaid.map(&:amount_in_cents).sum
  end

  def unpaid_donations_sum
    donations.unpaid.empty? ? 0 : donations.unpaid.map(&:amount).sum
  end

  def unpaid_spotus_donation
    spotus_donations.unpaid.first
  end

  def current_spotus_donation
    unpaid_spotus_donation || spotus_donations.build
  end

  def has_spotus_donation?
    spotus_donations.paid.any?
  end

  def paid_spotus_donations_sum
    has_spotus_donation? ? spotus_donations.paid.map(&:amount).sum : 0
  end

  def last_paid_spotus_donation
    spotus_donations.paid.last
  end

  def has_pledge_for?(tip)
    pledges.exists?(:tip_id => tip.id )
  end
  
  def to_s
    self.full_name
  end
  
  def to_param
    begin 
      "#{id}-#{to_s.parameterize}"
    rescue
      "#{id}"
    end
  end

  protected
  
  def encrypt_password
    self.salt = Digest::SHA1.hexdigest("--#{Time.now.to_s}--#{email}--") if new_record?
    self.crypted_password = encrypt(password)
  end

  def should_validate_password?
    #debugger
    (crypted_password.blank? || !password.blank?) && !facebook_user?
  end

  def deliver_signup_notification
    return if self.type == "Admin"
    Mailer.send(:"deliver_#{self.type.downcase}_signup_notification", self)
  end

  def deliver_activation_email
    Mailer.deliver_activation_email(self)
  end

  def generate_activation_code
    entropy = Time.now.to_s.split(//).sort_by{rand}.join
    digest = Digest::SHA1.hexdigest(entropy)
    self.activation_code = Zlib.crc32(digest)
  end

  def clear_activation_code
    self.update_attribute(:activation_code, nil)
  end
  



end


