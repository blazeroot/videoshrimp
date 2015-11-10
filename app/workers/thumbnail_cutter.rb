class ThumbnailCutter
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.png"
    _command = `ffmpeg -i #{video.video_file.path} -ss 00:00:01.000 -vframes 1 #{output}`
    if $?.to_i == 0
      video.thumbnail = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end
end