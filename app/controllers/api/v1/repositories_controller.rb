class Api::V1::RepositoriesController < Api::V1::ApplicationController
  include HostRedirect

  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    scope = @host.repositories.visible.order('last_synced_at DESC').includes(:host)
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('last_synced_at DESC')
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when @repositories, public: true
  end

  def lookup
    url = params[:url]
    priority = params[:priority].present?
    parsed_url = Addressable::URI.parse(url)
    @host = Host.find_by_domain(parsed_url.host)
    raise ActiveRecord::RecordNotFound unless @host
    path = parsed_url.path.delete_prefix('/').chomp('/')
    @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)
    if @repository
      @repository.sync_async(request.remote_ip, priority) unless @repository.last_synced_at.present? && @repository.last_synced_at > 1.day.ago
      redirect_to api_v1_host_repository_path(@host, @repository)
    else
      @host.sync_repository_async(path, request.remote_ip, priority) if path.present?
      redirect_to api_v1_host_repository_path(@host, path)
    end
  end

  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    fresh_when @repository, public: true
    @maintainers = @repository.issues.maintainers.group(:user).count.sort_by{|k,v| -v }
    @active_maintainers = @repository.issues.maintainers.where('issues.created_at > ?', 1.year.ago).group(:user).count.sort_by{|k,v| -v }
  end

  def ping
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    priority = params[:priority].present?
    if @repository
      @repository.sync_async(request.remote_ip, priority)
    else
      @host.sync_repository_async(params[:id], request.remote_ip, priority)
    end
    render json: { message: 'pong' }
  end
end