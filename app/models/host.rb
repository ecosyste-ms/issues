class Host < ApplicationRecord
  has_many :repositories
  has_many :issues

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validates :kind, presence: true

  scope :visible, -> { where('repositories_count > 0') }
  scope :with_issues, -> { where('issues_count > 0') }
  scope :with_pull_requests, -> { where('pull_requests_count > 0') }
  scope :with_authors, -> { where('authors_count > 0') }

  def self.find_by_name(name)
    Host.all.find { |host| host.name == name }
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

  def sync_repository_async(full_name, remote_ip = '0.0.0.0')
    repo = self.repositories.find_by('lower(full_name) = ?', full_name.downcase)
    repo = self.repositories.create(full_name: full_name) if repo.nil?
    
    job = Job.new(url: repo.html_url, status: 'pending', ip: remote_ip)
    if job.save
      job.sync_issues_async
    end
    job
  end

  def sync_recently_updated_repositories_async
    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    
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
    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    
    response = conn.get('/api/v1/hosts')
    return nil unless response.success?
    json = response.body

    json.each do |host|
      Host.find_or_create_by(name: host['name']).tap do |r|
        r.url = host['url']
        r.kind = host['kind']
        r.icon_url = host['icon_url']
        r.last_synced_at = Time.now
        r.save
      end
    end
  end
end
