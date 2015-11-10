class Mp4VideoEncoder
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    path = video.video_file.path
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.mp4"
    _command = `ffmpeg -i #{path} -f mp4 -vcodec h264 -acodec aac -strict -2 #{output}`
    if $?.to_i == 0
      video.mp4_file = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end
end