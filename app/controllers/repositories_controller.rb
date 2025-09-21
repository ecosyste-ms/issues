class RepositoriesController < ApplicationController
  include HostRedirect
  def lookup
    url = params[:url]
    priority = params[:priority].present?
    raise ActiveRecord::RecordNotFound unless url.present?
    parsed_url = Addressable::URI.parse(url)
    @host = Host.find_by_domain(parsed_url.host)
    raise ActiveRecord::RecordNotFound unless @host
    path = parsed_url.path.delete_prefix('/').chomp('/')
    @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)
    if @repository
      @repository.sync_async(request.remote_ip, priority) unless @repository.last_synced_at.present? && @repository.last_synced_at > 1.day.ago
      redirect_to host_repository_path(@host, @repository)
    elsif path.present?
      @job = @host.sync_repository_async(path, request.remote_ip, priority)
      @repository = @host.repositories.find_by('lower(full_name) = ?', path.downcase)
      raise ActiveRecord::RecordNotFound unless @repository
      redirect_to host_repository_path(@host, @repository)
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    redirect_to host_path(@host)
  end

  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened

    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    fresh_when(@repository, public: true)
    if @repository.nil?
      priority = params[:priority].present?
      @job = @host.sync_repository_async(params[:id], request.remote_ip, priority)
      @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
      raise ActiveRecord::RecordNotFound unless @repository
    end

    owner = Owner.find_by(host: @host, login: @repository.owner)
    raise ActiveRecord::RecordNotFound if owner&.hidden?

    issues_with_owners = @repository.issues.includes(:owner)
    hidden_users = issues_with_owners.map(&:owner).compact.select(&:hidden?).map(&:login).uniq

    @maintainers = @repository.issues.maintainers.group(:user).count
    @maintainers = @maintainers.reject { |user, _| hidden_users.include?(user) } if hidden_users.any?
    @maintainers = @maintainers.sort_by{|k,v| -v }.first(15)

    @active_maintainers = @repository.issues.maintainers.where('issues.created_at > ?', 1.year.ago).group(:user).count
    @active_maintainers = @active_maintainers.reject { |user, _| hidden_users.include?(user) } if hidden_users.any?
    @active_maintainers = @active_maintainers.sort_by{|k,v| -v }.first(15)
  end

  def charts
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    @period = (params[:period].presence || 'month')
    @exclude_bots = params[:exclude_bots].present?
    @start_date = params[:start_date].presence || @repository.issues.order(:created_at).first.created_at
    @end_date = params[:end_date].presence || Date.today

    start_date = params[:start_date].presence || @repository.issues.order(:created_at).first.created_at
    end_date = params[:end_date].presence || Date.today 

    scope = @repository.issues

    issues_with_owners = @repository.issues.includes(:owner)
    hidden_users = issues_with_owners.map(&:owner).compact.select(&:hidden?).map(&:login).uniq
    scope = scope.where.not(user: hidden_users) if hidden_users.any?

    scope = scope.created_after(start_date) if start_date.present?
    scope = scope.created_before(end_date) if end_date.present?

    if params[:exclude_bots] == 'true'
      scope = scope.human
    end

    if params[:only_bots] == 'true'
      scope = scope.bot
    end

    @max = params[:max].presence || round_up_to_nearest_50([scope.issue.group_by_period(@period, :created_at).count.values.max, scope.pull_request.group_by_period(@period, :created_at).count.values.max].max)
    fresh_when(@repository, public: true)
  end

  def chart_data
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    
    @repository = @host.repositories.find_by('lower(full_name) = ?', params[:id].downcase)
    
    period = (params[:period].presence || 'month').to_sym

    start_date = params[:start_date].presence || @repository.issues.order(:created_at).first.created_at
    end_date = params[:end_date].presence || Date.today 

    scope = @repository.issues

    issues_with_owners = @repository.issues.includes(:owner)
    hidden_users = issues_with_owners.map(&:owner).compact.select(&:hidden?).map(&:login).uniq
    scope = scope.where.not(user: hidden_users) if hidden_users.any?

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
      data = scope.issue.closed.group_by_period(period, :closed_at).count
    when 'issue_authors'
      data = scope.issue.group_by_period(period, :created_at).distinct.count(:user)
    when 'issue_average_time_to_close'
      data = scope.issue.closed.group_by_period(period, :closed_at).average(:time_to_close)
      data.update(data){ |_,v| v.to_f.seconds.in_days.to_i }
    when 'pull_requests_opened'
      data = scope.pull_request.group_by_period(period, :created_at).count
    when 'pull_requests_closed'
      data = scope.pull_request.group_by_period(period, :closed_at).count
    when 'pull_requests_merged'
      data = scope.pull_request.merged.group_by_period(period, :merged_at).count
    when 'pull_requests_not_merged'
      data = scope.pull_request.not_merged.group_by_period(period, :closed_at).count
    when 'pull_request_authors'
      data = scope.pull_request.group_by_period(period, :created_at).distinct.count(:user)
    when 'pull_request_average_time_to_close'
      data = scope.pull_request.closed.group_by_period(period, :closed_at).average(:time_to_close)
      data.update(data){ |_,v| v.to_f.seconds.in_days.to_i }
    when 'pull_request_average_time_to_merge'
      data = scope.pull_request.merged.group_by_period(period, :merged_at).average(:time_to_close)
      data.update(data){ |_,v| v.to_f.seconds.in_days.to_i }
    end
    
    ## TODO no data for these yet
    # Number of issue comments
    # Average number of comments per issue
    # Number of pull request comments
    # Average number of comments per pull request
    # Average time to first issue response
    # Average time to first pull request response
    # Number of new issue authors
    # Number of new pull request authors

    render json: data
    fresh_when(@repository, public: true)
  end

  private

  def round_up_to_nearest_50(n)
    ((n / 50.0).ceil) * 50
  end
end