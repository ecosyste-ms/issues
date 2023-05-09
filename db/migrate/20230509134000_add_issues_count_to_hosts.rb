class AddIssuesCountToHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :hosts, :issues_count, :integer
    add_column :hosts, :pull_requests_count, :integer
  end
end
