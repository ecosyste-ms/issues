class AddBotCountsToRepositories < ActiveRecord::Migration[7.0]
  def change
    add_column :repositories, :bot_issues_count, :integer
    add_column :repositories, :bot_pull_requests_count, :integer
  end
end
