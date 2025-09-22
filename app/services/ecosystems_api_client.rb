module EcosystemsApiClient
  def self.client(base_url)
    Faraday.new(base_url) do |f|
      f.request :json
      f.request :retry
      f.response :json
      f.headers['X-Requested-By'] = 'issues.ecosyste.ms'
      f.headers['User-Agent'] = 'issues.ecosyste.ms'
      f.headers['X-API-Key'] = ENV['ECOSYSTEMS_API_KEY'] if ENV['ECOSYSTEMS_API_KEY']
    end
  end
end