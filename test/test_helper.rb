ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require 'webmock/minitest'
require 'mocha/minitest'

require 'sidekiq_unique_jobs/testing'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

require_relative 'support/test_data_helpers'

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods
  include TestDataHelpers
  
  # Clean up database between tests
  self.use_transactional_tests = true
  
  Shoulda::Matchers.configure do |config|
    config.integrate do |with|
      with.test_framework :minitest
      with.library :rails
    end
  end
end
