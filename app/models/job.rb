class Job < ApplicationRecord
  validates_presence_of :url
  validates_uniqueness_of :id

  scope :status, ->(status) { where(status: status) }

  def self.check_statuses
    Job.where(status: ["queued", "working"]).find_each(&:check_status)
  end

  def self.clean_up
    Job.status(["complete",'error']).where('created_at < ?', 1.day.ago).delete_all
  end

  def check_status
    return if sidekiq_id.blank?
    return if finished?
    update(status: fetch_status)
  end

  def fetch_status
    Sidekiq::Status.status(sidekiq_id).presence || 'pending'
  end

  def in_progress?
    ['pending','queued', 'working'].include?(status)
  end

  def finished?
    ['complete', 'error'].include?(status)
  end

  def sync_issues_async(priority = false)
    if priority
      sidekiq_id = SyncIssuesWorker.perform_with_priority(id, priority)
    else
      sidekiq_id = SyncIssuesWorker.perform_async(id)
    end
    update(sidekiq_id: sidekiq_id)
  end

  def perform_issue_syncing
    begin
      results = sync_issues
      update!(results: results, status: 'complete')      
    rescue => e
      update(results: {error: e.inspect}, status: 'error')
    end
  end

  def sync_issues
    # TODO don't depend on the repos service being up
    conn = EcosystemsApiClient.client('https://repos.ecosyste.ms')
    
    response = conn.get("api/v1/repositories/lookup?url=#{CGI.escape(url)}")
    return nil unless response.success?
    json = response.body

    host = Host.find_by(name: json['host']['name'])
    repo = host.repositories.find_by('lower(full_name) = ?', json['full_name'].downcase)
    repo = host.repositories.create(full_name: json['full_name']) if repo.nil?
    
    repo.sync_issues
    
    results = repo.as_json
    return results
  end
end
