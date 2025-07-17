class AddUniqueLowerNameIndexToHosts < ActiveRecord::Migration[8.0]
  def change
    # Remove the old index if it exists
    remove_index :hosts, :name if index_exists?(:hosts, :name)
    
    # Add case-insensitive unique index
    add_index :hosts, 'LOWER(name)', unique: true, name: 'index_hosts_on_lower_name'
  end
end
