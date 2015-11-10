class CreateVideos < ActiveRecord::Migration
  def change
    create_table :videos do |t|
      t.string :name
      t.string :description
      t.text :video_data
      t.references :user, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
