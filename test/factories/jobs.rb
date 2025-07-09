FactoryBot.define do
  factory :job do
    sidekiq_id { SecureRandom.hex(12) }
    status { 'pending' }
    url { "https://github.com/rails/rails" }
    ip { '127.0.0.1' }
    results { {} }
    
    trait :completed do
      status { 'completed' }
      results { { issues_synced: 100, pull_requests_synced: 50 } }
    end
    
    trait :failed do
      status { 'failed' }
      results { { error: 'Repository not found' } }
    end
    
    trait :processing do
      status { 'processing' }
    end
  end
end