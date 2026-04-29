class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.integer :repository_id, null: false
      t.integer :issue_id
      t.integer :host_id, null: false
      t.string :uuid, null: false
      t.string :node_id
      t.integer :pull_request_number, null: false
      t.string :user
      t.string :state
      t.string :author_association
      t.text :body
      t.string :commit_id
      t.datetime :submitted_at

      t.timestamps
    end

    add_index :reviews, [:host_id, :uuid], unique: true
    add_index :reviews, [:repository_id, :pull_request_number]
    add_index :reviews, :issue_id
    add_index :reviews, :user
  end
end
