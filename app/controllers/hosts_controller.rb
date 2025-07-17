class HostsController < ApplicationController
  def index
    @hosts = Host.all.visible.with_authors.order('repositories_count DESC')

    @scope = Repository.visible.order('last_synced_at DESC').includes(:host)
    @pagy, @repositories = pagy_countless(@scope, items: 10)
    fresh_when(@repositories, public: true)
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
        redirect_to host_path(@host.name), status: :moved_permanently
        return
      end
    end
    
    # If still not found, raise error
    raise ActiveRecord::RecordNotFound.new("Couldn't find Host with name=#{host_name}") unless @host

    scope = @host.repositories.visible

    sort = params[:sort].presence || 'last_synced_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when(@repositories, public: true)
  end
end