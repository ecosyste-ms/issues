class AddDependencyMetadataToIssues < ActiveRecord::Migration[7.0]
  def change
    add_column :issues, :dependency_metadata, :json
  end
end
