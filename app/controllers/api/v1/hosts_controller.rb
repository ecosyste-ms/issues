class Api::V1::HostsController < Api::V1::ApplicationController
  include HostRedirect
  
  def index
    @hosts = Host.all.visible.order('repositories_count DESC')
    fresh_when @hosts, public: true
  end

  def show
    host_name = params[:id]
    
    # Try to find exact match first
    @host = Host.find_by(name: host_name)
    
    # If not found, try case-insensitive search
    unless @host
      @host = Host.find_by('LOWER(name) = ?', host_name.downcase)
      
      # If found with different case, redirect to correct case
      if @host && @host.name != host_name
        redirect_to api_v1_host_path(@host.name), status: :moved_permanently
        return
      end
    end
    
    # If still not found, raise error
    raise ActiveRecord::RecordNotFound.new("Couldn't find Host with name=#{host_name}") unless @host
    
    fresh_when @host, public: true
  end
end