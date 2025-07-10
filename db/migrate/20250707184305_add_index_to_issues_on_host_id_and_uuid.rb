class AddIndexToIssuesOnHostIdAndUuid < ActiveRecord::Migration[8.0]

  def change
    add_index :issues, [:host_id, :uuid], unique: true, name: 'index_issues_on_host_id_and_uuid'
  end
end
