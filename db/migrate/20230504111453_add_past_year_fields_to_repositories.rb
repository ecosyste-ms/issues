class AddPastYearFieldsToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :past_year_issues_count, :integer
    add_column :repositories, :past_year_pull_requests_count, :integer
    add_column :repositories, :past_year_avg_time_to_close_issue, :float
    add_column :repositories, :past_year_avg_time_to_close_pull_request, :float
    add_column :repositories, :past_year_issues_closed_count, :integer
    add_column :repositories, :past_year_pull_requests_closed_count, :integer
    add_column :repositories, :past_year_pull_request_authors_count, :integer
    add_column :repositories, :past_year_issue_authors_count, :integer
    add_column :repositories, :past_year_avg_comments_per_issue, :float
    add_column :repositories, :past_year_avg_comments_per_pull_request, :float
    add_column :repositories, :past_year_bot_issues_count, :integer
    add_column :repositories, :past_year_bot_pull_requests_count, :integer
  end
end
