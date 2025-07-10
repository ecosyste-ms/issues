class SyncIssuesWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker
  
  sidekiq_options queue: :default

  def perform(job_id)
    Job.find_by_id!(job_id).perform_issue_syncing
  end
  
  # Enqueue job to specific queue based on priority
  def self.perform_with_priority(job_id, priority = false)
    queue = priority ? :high_priority : :default
    
    result = client_push('class' => self, 'args' => [job_id], 'queue' => queue)
    result['jid'] # Return the Sidekiq job ID
  end
end