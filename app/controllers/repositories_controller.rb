class RepositoriesController < ApplicationController
  def lookup
    url = params[:url]
    parsed_url = Addressable::URI.parse(url)
    @host = Host.find_by_domain(parsed_url.host)
    raise ActiveRecord::RecordNotFound unless @host
    path = parsed_url.path.delete_prefix('/').chomp('/')
    @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)
    if @repository
      @repository.sync_async(request.remote_ip) unless @repository.last_synced_at.present? && @repository.last_synced_at > 1.day.ago
      redirect_to host_repository_path(@host, @repository)
    elsif path.present?
      @job = @host.sync_repository_async(path, request.remote_ip)
      @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)
      raise ActiveRecord::RecordNotFound unless @repository
      redirect_to host_repository_path(@host, @repository)
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    if @repository.nil?
      @job = @host.sync_repository_async(params[:id], request.remote_ip)
      @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
      raise ActiveRecord::RecordNotFound unless @repository
    end
  end
end