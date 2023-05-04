namespace :repositories do
  desc 'sync least recently synced repos'
  task sync_least_recent: :environment do 
      Repository.sync_least_recently_synced
  end
end