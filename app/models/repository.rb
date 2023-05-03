class Repository < ApplicationRecord
  belongs_to :host

  validates :full_name, presence: true

  scope :active, -> { where(status: nil) }
  scope :visible, -> { active.where.not(last_synced_at: nil) }
  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }

  def self.sync_least_recently_synced
    Repository.active.order('last_synced_at ASC').limit(1000).each(&:sync_async)
  end

  def to_s
    full_name
  end

  def to_param
    full_name
  end

  def subgroups
    return [] if full_name.split('/').size < 3
    full_name.split('/')[1..-2]
  end

  def project_slug
    full_name.split('/').last
  end

  def project_name
    full_name.split('/')[1..-1].join('/')
  end

  def owner
    full_name.split('/').first
  end

  def sync_async(remote_ip = '0.0.0.0')
    job = Job.new(url: html_url, status: 'pending', ip: remote_ip)
    if job.save
      job.parse_commits_async
    end
  end

  def sync_details
    conn = Faraday.new(repos_api_url) do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    response = conn.get
    if response.status == 404
      self.status = 'not_found'
      self.save
      return
    end
    return if response.status != 200
    json = response.body

    self.status = json['status']
    self.default_branch = json['default_branch']
    self.save    
  end

  def repos_url
    "https://repos.ecosyste.ms/hosts/#{host.name}/repositories/#{full_name}"
  end

  def repos_api_url
    "https://repos.ecosyste.ms/api/v1/hosts/#{host.name}/repositories/#{full_name}"
  end

  def html_url
    "#{host.url}/#{full_name}"
  end

  # TODO sync issues
end
