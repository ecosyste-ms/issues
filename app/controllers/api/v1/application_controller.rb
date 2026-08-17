class Api::V1::ApplicationController < ApplicationController
  before_action :set_api_cache_headers
  after_action { pagy_headers_merge(@pagy) if @pagy }

  def set_api_cache_headers
    set_cache_headers(cdn_ttl: 1.hour)
  end

  def render_pending_repository(repository)
    response.cache_control.replace(no_store: true)
    response.headers['Retry-After'] = '60'

    render json: {
      status: 'pending',
      repository_url: api_v1_host_repository_url(repository.host, repository),
      issues_url: api_v1_host_repository_issues_url(repository.host, repository)
    }, status: :accepted
  end
end
