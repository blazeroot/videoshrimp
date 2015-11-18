class WebmVideoEncoder
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    path = video.video_file.path
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.webm"
    _command = `ffmpeg -i #{path} -f webm -c:v libvpx -b:v 1M -c:a libvorbis #{output}`
    if $?.to_i == 0
      video.webm_file = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end

end