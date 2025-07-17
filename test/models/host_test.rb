require 'test_helper'

class HostTest < ActiveSupport::TestCase
  test 'should not allow duplicate host names with different cases' do
    # Create first host
    host1 = create_host(name: 'github.com', url: 'https://github.com', kind: 'github')
    
    # Try to create duplicate with different case
    host2 = Host.new(name: 'GitHub.com', url: 'https://github.com', kind: 'github')
    
    assert_not host2.valid?
    assert_includes host2.errors[:name], 'has already been taken'
  end
  
  test 'should not allow duplicate host names with uppercase' do
    # Create first host
    host1 = create_host(name: 'codeberg.org', url: 'https://codeberg.org', kind: 'forgejo')
    
    # Try to create duplicate with uppercase
    host2 = Host.new(name: 'CODEBERG.ORG', url: 'https://codeberg.org', kind: 'forgejo')
    
    assert_not host2.valid?
    assert_includes host2.errors[:name], 'has already been taken'
  end
  
  test 'should allow same host name with exact case' do
    # Create host
    host1 = create_host(name: 'gitea.com', url: 'https://gitea.com', kind: 'gitea')
    
    # Try to update same host (should work)
    host1.url = 'https://gitea.com/updated'
    assert host1.valid?
  end
  
  test 'should enforce database constraint' do
    # Create first host
    host1 = create_host(name: 'gitlab.com', url: 'https://gitlab.com', kind: 'gitlab')
    
    # Try to bypass validation and create duplicate directly
    assert_raises(ActiveRecord::RecordNotUnique) do
      # Use insert to bypass ActiveRecord validations
      Host.connection.execute("INSERT INTO hosts (name, url, kind, created_at, updated_at) VALUES ('GitLab.com', 'https://gitlab.com', 'gitlab', NOW(), NOW())")
    end
  end
  
  test 'should require name presence' do
    host = Host.new(url: 'https://example.com', kind: 'github')
    
    assert_not host.valid?
    assert_includes host.errors[:name], "can't be blank"
  end
  
  test 'should require url presence' do
    host = Host.new(name: 'example.com', kind: 'github')
    
    assert_not host.valid?
    assert_includes host.errors[:url], "can't be blank"
  end
  
  test 'should require kind presence' do
    host = Host.new(name: 'example.com', url: 'https://example.com')
    
    assert_not host.valid?
    assert_includes host.errors[:kind], "can't be blank"
  end
  
  test 'sync_all should create hosts with original names and prevent duplicates' do
    # Mock the API response
    api_response = [
      { 'name' => 'GitHub', 'url' => 'https://github.com', 'kind' => 'github', 'icon_url' => 'https://github.com/favicon.ico' },
      { 'name' => 'GitLab.com', 'url' => 'https://gitlab.com', 'kind' => 'gitlab', 'icon_url' => 'https://gitlab.com/favicon.ico' }
    ]
    
    # Mock the HTTP client
    conn = mock()
    response = mock()
    response.stubs(:success?).returns(true)
    response.stubs(:body).returns(api_response)
    conn.stubs(:get).returns(response)
    EcosystemsApiClient.stubs(:client).returns(conn)
    
    # Call sync_all
    Host.sync_all
    
    # Verify hosts were created with original names
    assert_equal 2, Host.count
    assert Host.exists?(name: 'GitHub')
    assert Host.exists?(name: 'GitLab.com')
  end

  test 'sync_all should update existing hosts without changing name case' do
    # Create existing host
    existing_host = create_host(name: 'GitHub', url: 'https://old-github.com', kind: 'github')
    
    # Mock API response with different case
    api_response = [
      { 'name' => 'github', 'url' => 'https://github.com', 'kind' => 'github', 'icon_url' => 'https://github.com/favicon.ico' }
    ]
    
    # Mock the HTTP client
    conn = mock()
    response = mock()
    response.stubs(:success?).returns(true)
    response.stubs(:body).returns(api_response)
    conn.stubs(:get).returns(response)
    EcosystemsApiClient.stubs(:client).returns(conn)
    
    # Call sync_all
    Host.sync_all
    
    # Verify existing host was updated but name case preserved
    assert_equal 1, Host.count
    updated_host = Host.first
    assert_equal 'GitHub', updated_host.name # Original case preserved
    assert_equal 'https://github.com', updated_host.url # URL updated
  end
end