class AddOwnerToRepositories < ActiveRecord::Migration[7.1]
  def change
    add_column :repositories, :owner, :string
  end
end
