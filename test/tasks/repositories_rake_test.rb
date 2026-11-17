require 'test_helper'
require 'rake'

class RepositoriesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('repositories:sync_least_recent')
    @task = Rake::Task['repositories:sync_least_recent']
    @task.reenable
  end

  test 'sync_least_recent queues never-synced repositories first' do
    host = create(:host, kind: 'gitlab', name: 'gitlab.com', url: 'https://gitlab.com')
    synced = create(:repository, host: host, full_name: 'group/synced', last_synced_at: 3.days.ago)
    never = create(:repository, host: host, full_name: 'group/never', last_synced_at: nil)

    @task.invoke

    assert_equal [never.html_url, synced.html_url], Job.order(:created_at).pluck(:url)
  end
end
