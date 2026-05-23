FactoryBot.define do
  factory :owner do
    host
    sequence(:login) { |n| "owner#{n}" }
    hidden { false }
  end
end
