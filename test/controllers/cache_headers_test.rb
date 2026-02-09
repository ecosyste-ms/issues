require 'test_helper'

class CacheHeadersTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    @repository.update!(last_synced_at: 1.hour.ago) if @repository.last_synced_at.nil?
  end

  test "home index sets public cache headers with s-maxage" do
    get root_path
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=21600"
    assert_cache_control "stale-while-revalidate=21600"
    assert_cache_control "stale-if-error=86400"
  end

  test "hosts index sets public cache headers" do
    get hosts_path
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=21600"
  end

  test "hosts show sets public cache headers" do
    get host_path(@host.name)
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=21600"
  end

  test "api hosts index sets shorter s-maxage" do
    get api_v1_hosts_path
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=3600"
  end

  test "api host show sets shorter s-maxage" do
    get api_v1_host_path(@host.name)
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=3600"
  end

  def assert_cache_control(directive)
    cc = response.headers['Cache-Control'] || ''
    assert cc.include?(directive), "Expected Cache-Control to include '#{directive}', got '#{cc}'"
  end
end
