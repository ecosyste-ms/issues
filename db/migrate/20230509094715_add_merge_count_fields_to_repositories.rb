class AddMergeCountFieldsToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :merged_pull_requests_count, :integer
    add_column :repositories, :past_year_merged_pull_requests_count, :integer
    add_column :issues, :merged_at, :datetime
  end
end
