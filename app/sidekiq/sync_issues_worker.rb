class SyncIssuesWorker
  include Sidekiq::Worker
  include Sidekiq::Status::Worker
  
  sidekiq_options queue: :default, lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(job_id, full = false)
    Job.find_by_id!(job_id).perform_issue_syncing(full)
  end
  
  # Enqueue job to specific queue based on priority
  def self.perform_with_priority(job_id, priority = false, full = false)
    queue = priority ? :high_priority : :default

    args = [job_id]
    args << true if full
    result = client_push('class' => self, 'args' => args, 'queue' => queue)
    result['jid'] # Return the Sidekiq job ID
  end
end
