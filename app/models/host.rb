class Host < ApplicationRecord
  has_many :repositories
  has_many :issues

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :url, presence: true
  validates :kind, presence: true

  scope :visible, -> { where('repositories_count > 0') }
  scope :with_issues, -> { where('issues_count > 0') }
  scope :with_pull_requests, -> { where('pull_requests_count > 0') }
  scope :with_authors, -> { where('authors_count > 0') }

  def self.find_by_name(name)
    Host.all.find { |host| host.name == name }
  end

  def self.find_by_name!(name)
    find_by_name(name) || raise(ActiveRecord::RecordNotFound.new("Couldn't find Host with name=#{name}"))
  end

  def self.find_by_domain(domain)
    Host.all.find { |host| host.domain == domain }
  end

  def host_class
    "Hosts::#{kind.capitalize}".constantize
  end

  def host_instance
    host_class.new(self)
  end

  def to_s
    name
  end

  def to_param
    name
  end

  def domain
    Addressable::URI.parse(url).host
  end

  def display_kind?
    return false if name.split('.').length == 2 && name.split('.').first.downcase == kind
    name.downcase != kind
  end

  def hidden?
    repositories_count == 0
  end

  def online?
    status == 'online'
  end

  def can_be_indexed?
    return true if status.blank? # Allow indexing for hosts without status info yet
    online? && (can_crawl_api.nil? || can_crawl_api)
  end

  def status_display
    case status
    when 'online'
      'Online'
    when 'timeout'
      'Timeout'
    when 'connection_failed'
      'Connection Failed'
    when 'http_error'
      'HTTP Error'
    when 'ssl_error'
      'SSL Error'
    when 'error'
      'Error'
    else
      'Unknown'
    end
  end

  def sync_repository_async(full_name, remote_ip = '0.0.0.0', priority = false)
    return nil unless can_be_indexed?
    
    repo = self.repositories.find_by('lower(full_name) = ?', full_name.downcase)
    repo = self.repositories.create(full_name: full_name) if repo.nil?
    
    job = Job.new(url: repo.html_url, status: 'pending', ip: remote_ip)
    if job.save
      job.sync_issues_async(priority)
    end
    job
  end

  def sync_recently_updated_repositories_async
    return nil unless can_be_indexed?
    
    conn = EcosystemsApiClient.client('https://repos.ecosyste.ms')
    
    response = conn.get('/api/v1/hosts/' + name + '/repositories')
    return nil unless response.success?
    json = response.body

    json.each do |repo|
      puts "syncing #{repo['full_name']}"
      sync_repository_async(repo['full_name'])
    end
  end 

  def self.update_counts
    Host.all.each(&:update_counts)
  end

  def update_counts
    self.repositories_count = repositories.visible.count
    self.issues_count = repositories.visible.sum(:issues_count)
    self.pull_requests_count = repositories.visible.sum(:pull_requests_count)
    self.authors_count = issues.distinct.count(:user)
    save
  end

  def self.sync_all
    conn = EcosystemsApiClient.client('https://repos.ecosyste.ms')
    
    response = conn.get('/api/v1/hosts')
    return nil unless response.success?
    json = response.body

    json.each do |host|
      # Find existing host case-insensitively
      existing_host = Host.find_by('LOWER(name) = ?', host['name'].downcase)
      
      if existing_host
        # Update existing host but preserve its name
        existing_host.tap do |r|
          r.url = host['url']
          r.kind = host['kind']
          r.icon_url = host['icon_url']
          r.owners_count = host['owners_count']
          r.status = host['status']
          r.online = host['online']
          r.status_checked_at = host['status_checked_at']
          r.response_time = host['response_time']
          r.last_error = host['last_error']
          r.can_crawl_api = host['can_crawl_api']
          r.host_url = host['host_url']
          r.repositories_url = host['repositories_url']
          r.owners_url = host['owners_url']
          r.last_synced_at = Time.now
          r.save
        end
      else
        # Create new host with original name
        Host.create!(
          name: host['name'],
          url: host['url'],
          kind: host['kind'],
          icon_url: host['icon_url'],
          owners_count: host['owners_count'],
          status: host['status'],
          online: host['online'],
          status_checked_at: host['status_checked_at'],
          response_time: host['response_time'],
          last_error: host['last_error'],
          can_crawl_api: host['can_crawl_api'],
          host_url: host['host_url'],
          repositories_url: host['repositories_url'],
          owners_url: host['owners_url'],
          last_synced_at: Time.now
        )
      end
    end
  end
end
