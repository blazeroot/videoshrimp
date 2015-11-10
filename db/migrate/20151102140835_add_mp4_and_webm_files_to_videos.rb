class AddMp4AndWebmFilesToVideos < ActiveRecord::Migration
  def change
    add_attachment :videos, :mp4_file
    add_attachment :videos, :webm_file
    add_attachment :videos, :ogg_file
  end
end
