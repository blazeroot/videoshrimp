class AddLikesToVideos < ActiveRecord::Migration
  def change
    add_column :videos, :likes, :integer, default: 0
  end
end
