require 'test_helper'
require 'rake'

class IssuesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('issues:reconcile')
    @task = Rake::Task['issues:reconcile']
    @task.reenable
  end

  test 'reconcile performs a full repository reconciliation' do
    host = create_or_find_github_host
    repository = create(:repository, host: host, full_name: 'observablehq/notebook-kit')
    Repository.any_instance.expects(:reconcile).once

    output, = capture_io { @task.invoke('GitHub', repository.full_name) }

    assert_includes output, "Reconciled #{repository.full_name}"
  end

  test 'reconcile aborts without repository arguments' do
    assert_raises(SystemExit) do
      capture_io { @task.invoke }
    end
  end
end
