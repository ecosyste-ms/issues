require "test_helper"
require "rake"

class TakedownRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("takedown:hide_user")
    @host = create(:host, :github)
  end

  teardown do
    ENV.delete('LOGIN')
    ENV.delete('HOST')
  end

  test "hide_user marks owner hidden and destroys repositories" do
    owner = create(:owner, host: @host, login: 'someuser')
    repo = create(:repository, host: @host, full_name: 'someuser/thing', owner: 'someuser')
    create(:issue, repository: repo, host: @host)
    other = create(:repository, host: @host, full_name: 'other/thing', owner: 'other')

    ENV['LOGIN'] = 'someuser'
    capture_io { Rake::Task["takedown:hide_user"].execute }

    assert owner.reload.hidden?
    assert_nil Repository.find_by(id: repo.id)
    assert_equal 0, Issue.where(repository_id: repo.id).count
    refute_nil Repository.find_by(id: other.id)
  end

  test "hide_user creates a hidden owner when none exists" do
    ENV['LOGIN'] = 'newuser'
    capture_io { Rake::Task["takedown:hide_user"].execute }

    owner = @host.owners.find_by('lower(login) = ?', 'newuser')
    refute_nil owner
    assert owner.hidden?
  end

  test "hide_user aborts without LOGIN" do
    assert_raises(SystemExit) do
      capture_io { Rake::Task["takedown:hide_user"].execute }
    end
  end
end
