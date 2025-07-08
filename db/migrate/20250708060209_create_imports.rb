class CreateImports < ActiveRecord::Migration[8.0]
  def change
    create_table :imports do |t|
      t.string :filename
      t.datetime :imported_at
      t.integer :issues_count
      t.integer :pull_requests_count
      t.integer :created_count
      t.integer :updated_count
      t.boolean :success
      t.text :error_message

      t.timestamps
    end
    add_index :imports, :filename, unique: true
  end
end
