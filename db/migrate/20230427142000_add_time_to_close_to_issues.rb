class AddTimeToCloseToIssues < ActiveRecord::Migration[7.0]
  def change
    add_column :issues, :time_to_close, :integer
  end
end
