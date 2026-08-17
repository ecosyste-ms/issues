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
end
