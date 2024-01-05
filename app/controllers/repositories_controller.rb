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

  def charts
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    @period = (params[:period].presence || 'month')
    @exclude_bots = params[:exclude_bots].present?
    @start_date = params[:start_date].presence || @repository.issues.order(:created_at).first.created_at
    @end_date = params[:end_date].presence || Date.today
  end

  def chart_data
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    
    period = (params[:period].presence || 'month').to_sym

    start_date = params[:start_date].presence || @repository.issues.order(:created_at).first.created_at
    end_date = params[:end_date].presence || Date.today 

    scope = @repository.issues

    scope = scope.created_after(start_date) if start_date.present?
    scope = scope.created_before(end_date) if end_date.present?

    if params[:exclude_bots] == 'true'
      scope = scope.human
    end

    if params[:only_bots] == 'true'
      scope = scope.bot
    end

    case params[:chart]
    when 'issues_opened'
      data = scope.issue.group_by_period(period, :created_at).count
    when 'issues_closed'
      data = scope.issue.group_by_period(period, :closed_at).count
    when 'pull_requests_opened'
      data = scope.pull_request.group_by_period(period, :created_at).count
    when 'pull_requests_closed'
      data = scope.pull_request.group_by_period(period, :closed_at).count
    when 'pull_requests_merged'
      data = scope.pull_request.merged.group_by_period(period, :merged_at).count
    end
    
    # TODO: add these
    # Average time to close issues
    # Number of unique issue authors
    # Number of unique pull request authors
    # Average time to first issue response
    # Average time to first pull request response
    # Number of new issue authors
    # Number of new pull request authors


    ## TODO no data for these yet
    # Number of issue comments
    # Average number of comments per issue
    # Number of pull request comments
    # Average number of comments per pull request

    render json: data
  end
end