class OgvVideoEncoder
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    path = video.video_file.path
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.ogv"
    _command = `ffmpeg -i #{path} -codec:v libtheora -qscale:v 7 -codec:a libvorbis -qscale:a 7 #{output}`
    if $?.to_i == 0
      video.ogg_file = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end
end