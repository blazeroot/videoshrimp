class VideoPublisher
  include Sidekiq::Worker
  include Sidetiq::Schedulable

  recurrence { minutely }

  def perform
    Video.where(published: false).each do |video|
      video.publish! if video.all_formats_encoded?
    end
  end
end