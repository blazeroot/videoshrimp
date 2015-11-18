class CreateVideos < ActiveRecord::Migration
  def change
    create_table :videos do |t|
      t.string :name
      t.attachment :video_file
      t.attachment :mp4_file
      t.attachment :webm_file
      t.attachment :ogg_file
      t.attachment :thumbnail
      t.boolean :published
      t.integer :likes, default: 0
      t.references :user, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
