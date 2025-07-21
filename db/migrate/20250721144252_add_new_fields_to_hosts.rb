class AddNewFieldsToHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :hosts, :owners_count, :integer
    add_column :hosts, :status, :string
    add_column :hosts, :online, :boolean
    add_column :hosts, :status_checked_at, :datetime
    add_column :hosts, :response_time, :integer
    add_column :hosts, :last_error, :text
    add_column :hosts, :can_crawl_api, :boolean
    add_column :hosts, :host_url, :string
    add_column :hosts, :repositories_url, :string
    add_column :hosts, :owners_url, :string
  end
end
