class CreateExports < ActiveRecord::Migration[7.0]
  def change
    create_table :exports do |t|
      t.string :date
      t.string :bucket_name
      t.integer :issues_count

      t.timestamps
    end
  end
end
