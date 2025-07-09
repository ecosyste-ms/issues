class AddIndexToRepositoriesForStatusQuery < ActiveRecord::Migration[8.0]
  def change
    add_index :repositories, [:host_id, :last_synced_at],
              name: 'index_repositories_on_host_id_last_synced_at_null_status',
              where: "status IS NULL"
  end
end
