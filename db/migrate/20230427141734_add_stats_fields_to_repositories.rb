class AddStatsFieldsToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :pull_requests_count, :integer
    add_column :repositories, :avg_time_to_close_issue, :float
    add_column :repositories, :avg_time_to_close_pull_request, :float
    add_column :repositories, :issues_closed_count, :integer
    add_column :repositories, :pull_requests_closed_count, :integer
    add_column :repositories, :pull_request_authors_count, :integer
    add_column :repositories, :issue_authors_count, :integer
    add_column :repositories, :avg_comments_per_issue, :float
    add_column :repositories, :avg_comments_per_pull_request, :float
  end
end
