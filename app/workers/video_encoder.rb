class VideoEncoder
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    create_video_data(video)
  end

  private

  def create_video_data(video)
    xml_video_info = `mediainfo --Output=XML #{video.video_file.path}`
    hash_video_info = Hash.from_xml xml_video_info
    video_info = Hash.new
    video_info[:general] = hash_video_info['Mediainfo']['File']['track'][0]
    video_info[:video]   = hash_video_info['Mediainfo']['File']['track'][1]
    video_info[:audio]   = hash_video_info['Mediainfo']['File']['track'][2]
    video.video_data = video_info
    video.save
  end
end