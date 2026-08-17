require 'test_helper'

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test 'renders 404 without caching it' do
    get '/404'
    assert_response :not_found
    assert_template 'errors/not_found'
    assert_includes response.headers['Cache-Control'], 'no-store'
    refute_match(/public|max-age|s-maxage/, response.headers['Cache-Control'])
  end

  test 'renders 422' do
    get '/422'
    assert_response :unprocessable_content
    assert_template 'errors/unprocessable'
  end

  test 'renders 500' do
    get '/500'
    assert_response :internal_server_error
    assert_template 'errors/internal'
  end
end
