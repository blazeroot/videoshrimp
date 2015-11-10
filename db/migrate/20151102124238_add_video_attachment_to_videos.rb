class AddVideoAttachmentToVideos < ActiveRecord::Migration
  def change
    add_attachment :videos, :video_file
  end
end
