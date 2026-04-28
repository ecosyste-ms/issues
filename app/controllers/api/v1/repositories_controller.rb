class Api::V1::RepositoriesController < Api::V1::ApplicationController
  before_action :find_host, only: [:index, :show, :ping, :chart_data]
  skip_before_action :set_cache_headers, only: [:lookup, :ping]
  skip_before_action :set_api_cache_headers, only: [:lookup, :ping]

  def index
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
    raise ActiveRecord::RecordNotFound unless parsed_url&.host
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
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    fresh_when @repository, public: true
    @maintainers = @repository.issues.maintainers.group(:user).count.sort_by{|k,v| -v }
    @active_maintainers = @repository.issues.maintainers.where('issues.created_at > ?', 1.year.ago).group(:user).count.sort_by{|k,v| -v }
  end

  def ping
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    priority = params[:priority].present?
    if @repository
      @repository.sync_async(request.remote_ip, priority)
    else
      @host.sync_repository_async(params[:id], request.remote_ip, priority)
    end
    render json: { message: 'pong' }
  end

  def chart_data
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    period = (params[:period].presence || 'month').to_sym

    scope = @repository.issues
    scope = scope.created_after(params[:start_date]) if params[:start_date].present?
    scope = scope.created_before(params[:end_date]) if params[:end_date].present?

    hidden_users = hidden_users_for(@repository)
    scope = scope.where.not(user: hidden_users) if hidden_users.any?

    if params[:exclude_bots] == 'true'
      scope = scope.human
    end

    if params[:only_bots] == 'true'
      scope = scope.bot
    end

    data = case params[:chart]
           when 'issues_opened'
             scope.issue.group_by_period(period, :created_at).count
           when 'issues_closed'
             scope.issue.closed.group_by_period(period, :closed_at).count
           when 'issue_authors'
             scope.issue.group_by_period(period, :created_at).distinct.count(:user)
           when 'issue_average_time_to_close'
             days(scope.issue.closed.group_by_period(period, :closed_at).average(:time_to_close))
           when 'pull_requests_opened'
             scope.pull_request.group_by_period(period, :created_at).count
           when 'pull_requests_closed'
             scope.pull_request.closed.group_by_period(period, :closed_at).count
           when 'pull_requests_merged'
             scope.pull_request.merged.group_by_period(period, :merged_at).count
           when 'pull_requests_not_merged'
             scope.pull_request.not_merged.group_by_period(period, :closed_at).count
           when 'pull_request_authors'
             scope.pull_request.group_by_period(period, :created_at).distinct.count(:user)
           when 'pull_request_average_time_to_close'
             days(scope.pull_request.closed.group_by_period(period, :closed_at).average(:time_to_close))
           when 'pull_request_average_time_to_merge'
             days(scope.pull_request.merged.group_by_period(period, :merged_at).average(:time_to_close))
           else
             render json: { error: 'unknown chart' }, status: :bad_request
             return
           end

    fresh_when @repository, public: true
    render json: data
  end

  private

  def days(data)
    data.transform_values { |value| value.to_f.seconds.in_days.to_i }
  end

  def hidden_users_for(repository)
    Owner.hidden
         .where(host_id: @host.id)
         .where(login: repository.issues.select(:user).distinct)
         .pluck(:login)
  end
end
