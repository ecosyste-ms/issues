class DropBodyFromIssues < ActiveRecord::Migration[7.0]
  def change
    remove_column :issues, :body, :text
  end
end
