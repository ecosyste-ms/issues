require 'test_helper'

class SyncIssuesWorkerTest < ActiveSupport::TestCase
  test 'perform passes full reconciliation to the job' do
    job = mock
    Job.expects(:find_by_id!).with('job-id').returns(job)
    job.expects(:perform_issue_syncing).with(true)

    SyncIssuesWorker.new.perform('job-id', true)
  end
end
