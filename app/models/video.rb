class Video < ActiveRecord::Base
  belongs_to :user
  serialize :video_info, Hash

  has_attached_file :video_file
  has_attached_file :mp4_file
  has_attached_file :webm_file
  has_attached_file :ogg_file
  has_attached_file :thumbnail, styles: { medium_nr: "250x150!" }

  validates_attachment_content_type :video_file, content_type: /\Avideo/
  validates_attachment_content_type :mp4_file, content_type: /.*/
  validates_attachment_content_type :webm_file, content_type: /.*/
  validates_attachment_content_type :ogg_file, content_type: /.*/

  validates_attachment_presence :video_file

  after_create :run_encoders

  def run_encoders
    ThumbnailCutter.perform_async(self.id)
    Mp4VideoEncoder.perform_async(self.id)
    OgvVideoEncoder.perform_async(self.id)
    WebmVideoEncoder.perform_async(self.id)
  end

  def publish!
    self.published = true
    save
    $pubnub.publish(channel: "video.#{id}", message: {event: :published}, http_sync: true)
    $pubnub.publish(channel: self.user.notification_channel, message: {event: :published, scope: :videos, id: self.id, name: name.truncate(20)}, http_sync: true)
  end

  def like!
    self.likes += 1
    save
    $pubnub.publish(channel: "video.#{id}", message: {event: :liked}, http_sync: true)
  end

  def dislike!
    self.likes -= 1
    save
    $pubnub.publish(channel: "video.#{id}", message: {event: :disliked}, http_sync: true)
  end

  def all_formats_encoded?
    self.webm_file.path && self.mp4_file.path && self.ogg_file.path ? true : false
  end
end
