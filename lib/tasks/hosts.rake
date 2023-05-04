namespace :hosts do
  desc 'update counts'
  task update_counts: :environment do
    Host.all.each(&:update_counts)
  end

  desc 'sync all'
  task sync_all: :environment do
    Host.sync_all
  end
end