class AddHostIdToIssues < ActiveRecord::Migration[7.0]
  def change
    add_column :issues, :host_id, :integer
    add_index :issues, [:host_id, :user]
  end
end
