namespace :takedown do
  desc "Hide a user and remove their repositories. LOGIN=username [HOST=GitHub]"
  task hide_user: :environment do
    login = ENV['LOGIN']
    host_name = ENV['HOST'] || 'GitHub'
    abort "LOGIN is required" if login.blank?

    host = Host.find_by_name(host_name)
    abort "Host #{host_name} not found" if host.nil?

    owner = host.owners.find_by('lower(login) = ?', login.downcase)
    owner ||= host.owners.create!(login: login)
    owner.update!(hidden: true)
    puts "[issues] hidden owner #{host.name}/#{owner.login}"

    repos = host.repositories.where('lower(owner) = ?', login.downcase)
    count = repos.count
    repos.find_each do |repo|
      puts "[issues] destroying #{repo.full_name} (#{repo.issues.count} issues)"
      repo.destroy
    end
    puts "[issues] destroyed #{count} repositories for #{host.name}/#{login}"
  end

  desc "Report what exists for a user. LOGIN=username [HOST=GitHub]"
  task report: :environment do
    login = ENV['LOGIN']
    host_name = ENV['HOST'] || 'GitHub'
    abort "LOGIN is required" if login.blank?

    host = Host.find_by_name(host_name)
    abort "Host #{host_name} not found" if host.nil?

    owner = host.owners.find_by('lower(login) = ?', login.downcase)
    repo_count = host.repositories.where('lower(owner) = ?', login.downcase).count
    authored_count = host.issues.where(user: login).count
    puts "[issues] #{host.name}/#{login}: owner=#{owner ? (owner.hidden? ? 'hidden' : 'visible') : 'none'} repositories=#{repo_count} authored_issues=#{authored_count}"
  end
end
