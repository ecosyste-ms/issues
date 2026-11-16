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

  test 'delete_gharchive_duplicates deletes replaced archive rows' do
    task = Rake::Task['issues:delete_gharchive_duplicates']
    task.reenable
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    duplicate = create(:issue, repository: repository, number: 1, pull_request: true, node_id: nil)
    create(:issue, repository: repository, number: 1, pull_request: true, node_id: 'PR_1')

    output, = capture_io { task.invoke }

    assert_includes output, 'Deleted 1 duplicate pull request rows'
    refute Issue.exists?(duplicate.id)
  end

  test 'delete_misplaced_github_rows reports the deleted count' do
    task = Rake::Task['issues:delete_misplaced_github_rows']
    task.reenable
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    create(:issue, repository: repository, number: 11079, node_id: 'PR_kwDOAiM0fc6p3Oet')
    %w[PR_kwDOAiM0fc6p3Oeu PR_kwDOAiM0fc6p3Oev PR_kwDOAiM0fc6p3Oew PR_kwDOAiM0fc6p3Oex PR_kwDOAiM0fc6p3Oey
       PR_kwDOAiM0fc6p3Oez PR_kwDOAiM0fc6p3Oe0 PR_kwDOAiM0fc6p3Oe1 PR_kwDOAiM0fc6p3Oe2].each_with_index do |node_id, i|
      create(:issue, repository: repository, number: 11463 + i, node_id: node_id)
    end
    misplaced = create(:issue, repository: repository, number: 11079, node_id: 'PR_kwDOC4MXqs5QpOOO')

    output, = capture_io { task.invoke }

    assert_includes output, 'Deleted 1 misplaced rows'
    refute Issue.exists?(misplaced.id)
  end

  test 'reconcile aborts without repository arguments' do
    assert_raises(SystemExit) do
      capture_io { @task.invoke }
    end
  end
end
