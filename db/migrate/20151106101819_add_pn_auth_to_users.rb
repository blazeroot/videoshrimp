class AddPnAuthToUsers < ActiveRecord::Migration
  def change
    add_column :users, :pn_auth_key, :string
  end
end
