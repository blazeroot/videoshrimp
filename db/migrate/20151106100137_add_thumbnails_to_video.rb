class AddThumbnailsToVideo < ActiveRecord::Migration
  def change
    add_attachment :videos, :thumbnail
  end
end
