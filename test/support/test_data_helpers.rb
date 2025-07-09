module TestDataHelpers
  # Wrapper methods that delegate to FactoryBot
  # These are kept for backward compatibility with existing tests
  
  def create_or_find_github_host
    Host.find_by(name: 'GitHub') || create(:host, :github)
  end
  
  def create_or_find_rails_repository(host)
    Repository.find_by(host: host, full_name: 'rails/rails') || create(:repository, :rails, host: host)
  end
  
  def create_repository(host, attributes = {})
    build(:repository, { host: host }.merge(attributes)).tap(&:save!)
  end

  def create_issue(repository, attributes = {})
    build(:issue, { repository: repository }.merge(attributes)).tap(&:save!)
  end

  def create_pull_request(repository, attributes = {})
    build(:issue, :pull_request, { repository: repository }.merge(attributes)).tap(&:save!)
  end

  def create_host(attributes = {})
    build(:host, attributes).tap(&:save!)
  end

  def create_dependency_metadata(issue, attributes = {})
    defaults = {
      ecosystem: 'rubygems',
      package_name: 'rails',
      current_version: '6.0.0',
      target_version: '6.1.0'
    }
    
    metadata = defaults.merge(attributes)
    issue.update!(dependency_metadata: metadata)
  end
end