class AddOwnerIndexToRepositories < ActiveRecord::Migration[7.1]
  def change
    add_index :repositories, :owner
  end
end
