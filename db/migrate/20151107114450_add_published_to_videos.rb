class AddPublishedToVideos < ActiveRecord::Migration
  def change
    add_column :videos, :published, :boolean, {default: false}
  end
end
