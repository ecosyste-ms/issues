class AddIndexToIssuesOnHostIdAndUuid < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    unless index_exists?(:issues, [:host_id, :uuid], name: 'index_issues_on_host_id_and_uuid')
      add_index :issues, [:host_id, :uuid], algorithm: :concurrently, unique: true, name: 'index_issues_on_host_id_and_uuid'
    end
  end
end
