class RemoveDependencyMetadataFromIssues < ActiveRecord::Migration[8.0]
  def change
    remove_column :issues, :dependency_metadata, :jsonb
  end
end
