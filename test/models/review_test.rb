require 'test_helper'

class ReviewTest < ActiveSupport::TestCase
  test "belongs to repository host and optional issue" do
    host = create(:host)
    repository = create(:repository, host: host)
    pull_request = create(:issue, repository: repository, host: host, pull_request: true, number: 42)

    review = Review.create!(
      host: host,
      repository: repository,
      issue: pull_request,
      uuid: 'review-1',
      pull_request_number: 42,
      user: 'reviewer',
      state: 'APPROVED'
    )

    assert_equal repository, review.repository
    assert_equal host, review.host
    assert_equal pull_request, review.issue
    assert_equal [review], Review.pull_request(42).to_a
    assert_equal [review], Review.state('APPROVED').to_a
  end
end
