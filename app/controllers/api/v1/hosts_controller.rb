class Api::V1::HostsController < Api::V1::ApplicationController
  before_action :find_host_by_id, only: [:show]

  def index
    @hosts = Host.all.visible.order('repositories_count DESC')
    fresh_when @hosts, public: true
  end

  def show
    fresh_when @host, public: true
  end
end
