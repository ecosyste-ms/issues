require 'test_helper'

class ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @export = create(:export, date: '2019-01-01', bucket_name: 'test-bucket', issues_count: 123)
  end

  test 'renders index' do
    get exports_path
    assert_response :success
    assert_template 'exports/index'
  end
end