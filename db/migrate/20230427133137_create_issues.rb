class CreateIssues < ActiveRecord::Migration[7.0]
  def change
    create_table :issues do |t|
      t.integer :repository_id
      t.string :uuid
      t.string :node_id
      t.integer :number
      t.string :state
      t.string :title
      t.text :body
      t.string :user
      t.string :labels, array: true, default: []
      t.string :assignees, array: true, default: []
      t.boolean :locked
      t.integer :comments_count
      t.boolean :pull_request
      t.datetime :closed_at
      t.string :author_association
      t.string :state_reason

      t.timestamps
    end

    add_index :issues, :repository_id
  end
end
