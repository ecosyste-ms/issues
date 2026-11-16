class AddRepositoryIdNumberIndexToIssues < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :issues, [:repository_id, :number], algorithm: :concurrently, if_not_exists: true
    remove_index :issues, :repository_id, algorithm: :concurrently, if_exists: true
  end
end
