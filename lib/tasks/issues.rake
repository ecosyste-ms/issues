namespace :issues do
  desc 'Fully reconcile a GitHub repository from the issues API'
  task :reconcile, [:host_name, :full_name] => :environment do |_task, args|
    unless args[:host_name].present? && args[:full_name].present?
      abort 'Usage: bin/rails issues:reconcile[GitHub,owner/repository]'
    end

    host = Host.find_by_name!(args[:host_name])
    repository = host.repositories.find_by!('lower(full_name) = ?', args[:full_name].downcase)
    repository.reconcile

    puts "Reconciled #{repository.full_name}: #{repository.issues_count} issues, #{repository.pull_requests_count} pull requests"
  end

  desc 'Delete GH Archive pull request rows that the issues API has replaced; pass a start id to resume'
  task :delete_gharchive_duplicates, [:from_id] => :environment do |_task, args|
    host = Host.find_by_name!('GitHub')
    from_id = args[:from_id].to_i
    deleted = Issue.delete_gharchive_duplicates(host, from_id: from_id) do |next_id, total|
      puts "next id #{next_id}: #{total} deleted" if (next_id - from_id) % 1_000_000 == 0
    end
    puts "Deleted #{deleted} duplicate pull request rows"
  end

  desc 'Delete GitHub rows attached to the wrong repository by a uuid collision; pass a start id to resume'
  task :delete_misplaced_github_rows, [:from_id] => :environment do |_task, args|
    host = Host.find_by_name!('GitHub')
    from_id = args[:from_id].to_i
    deleted = Issue.delete_misplaced_github_rows(host, from_id: from_id) do |next_id, total|
      puts "next id #{next_id}: #{total} deleted" if (next_id - from_id) % 1_000_000 == 0
    end
    puts "Deleted #{deleted} misplaced rows"
  end
end
