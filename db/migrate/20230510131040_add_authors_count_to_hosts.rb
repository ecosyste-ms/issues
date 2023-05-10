class AddAuthorsCountToHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :hosts, :authors_count, :integer
  end
end
