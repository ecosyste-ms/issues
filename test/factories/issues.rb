FactoryBot.define do
  factory :issue do
    association :repository
    host { repository.host }
    sequence(:number) { |n| n }
    state { 'open' }
    title { "Issue #{number}" }
    user { "user#{SecureRandom.hex(4)}" }
    labels { [] }
    assignees { [] }
    locked { false }
    comments_count { 0 }
    pull_request { false }
    closed_at { nil }
    author_association { nil }
    state_reason { nil }
    time_to_close { nil }
    merged_at { nil }
    
    trait :closed do
      state { 'closed' }
      closed_at { 1.day.ago }
      time_to_close { 86400 } # 1 day in seconds
    end
    
    trait :pull_request do
      pull_request { true }
      title { "Pull Request #{number}" }
    end
    
    trait :merged do
      pull_request { true }
      state { 'closed' }
      closed_at { 1.day.ago }
      merged_at { 1.day.ago }
      time_to_close { 86400 }
    end
    
    trait :bot do
      user { 'dependabot[bot]' }
    end
    
    trait :with_comments do
      comments_count { 10 }
    end
    
    trait :maintainer do
      author_association { 'MEMBER' }
    end
    
    trait :contributor do
      author_association { 'CONTRIBUTOR' }
    end
    
    trait :owner do
      author_association { 'OWNER' }
    end
  end
end