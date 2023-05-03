class CreateRepositories < ActiveRecord::Migration[7.0]
  def change
    create_table :repositories do |t|
      t.integer :host_id
      t.string :full_name
      t.string :default_branch
      t.datetime :last_synced_at
      t.integer :issues_count
      t.string :status

      t.timestamps
    end

    add_index :repositories, 'host_id, lower(full_name)', unique: true
  end
end
