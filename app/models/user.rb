class User < ActiveRecord::Base
  # Association declaration
  has_many :videos

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  after_create :gen_auth_and_grant_perms

  def notification_channel
    "notifications.#{self.id}"
  end

  def gen_auth_and_grant_perms
    generate_pn_auth!
    $pubnub.grant(
        channel: notification_channel,
        auth_key: pn_auth_key,
        ttl: 0,
        http_sync: true
    )
  end

  def generate_pn_auth
    self.pn_auth_key = SecureRandom.hex
  end

  def generate_pn_auth!
    self.generate_pn_auth
    save
  end
end
