class Repository < ApplicationRecord
  belongs_to :host

  has_many :issues, dependent: :delete_all

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
      job.sync_issues_async
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

  def issue_labels_count
    issues.where(pull_request: false).pluck(:labels).flatten.compact.group_by(&:itself).map{|k,v| [k, v.count]}.to_h.sort_by{|k,v| v}.reverse
  end

  def pull_request_labels_count
    issues.where(pull_request: true).pluck(:labels).flatten.compact.group_by(&:itself).map{|k,v| [k, v.count]}.to_h.sort_by{|k,v| v}.reverse
  end

  def bot_issues_count
    issues.where(pull_request: false).where('issues.user ILIKE ?', '%[bot]').count
  end

  def bot_pull_requests_count
    issues.where(pull_request: true).where('issues.user ILIKE ?', '%[bot]').count
  end

  # TODO sync issues
  def sync_issues
    remote_issues = host.host_instance.load_issues(self)
    remote_issues.each do |issue|
      i = issues.find_or_create_by(uuid: issue[:uuid])
      i.assign_attributes issue
      i.time_to_close = i.closed_at - i.created_at if i.closed_at.present?
      i.save
    end

    self.issues_count = issues.where(pull_request: false).count
    self.pull_requests_count = issues.where(pull_request: true).count

    # avg time to close issue
    self.avg_time_to_close_issue = issues.where(pull_request: false).average(:time_to_close)
    # avg time to close pull request
    self.avg_time_to_close_pull_request = issues.where(pull_request: true).average(:time_to_close)
    # number of issues closed
    self.issues_closed_count = issues.where(pull_request: false, state: 'closed').count
    # number of pull requests closed
    self.pull_requests_closed_count = issues.where(pull_request: true, state: 'closed').count
    # number of unqiue pull request authors
    self.pull_request_authors_count = issues.where(pull_request: true).distinct.count(:user)
    # number of unique issue authors
    self.issue_authors_count = issues.where(pull_request: false).distinct.count(:user)
    # avg number of comments per issue
    self.avg_comments_per_issue = issues.where(pull_request: false).average(:comments_count)
    # avg number of comments per pull request
    self.avg_comments_per_pull_request = issues.where(pull_request: true).average(:comments_count)

    self.last_synced_at = Time.now
    self.save
  end
end
