class Api::V1::IssuesController < Api::V1::ApplicationController
  include HostRedirect
  
  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    
    scope = @repository.issues

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    scope = scope.where(pull_request: params[:pull_request]) if params[:pull_request].present?
    scope = scope.where(state: params[:state]) if params[:state].present?
    scope = scope.label(params[:label]) if params[:label].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'number'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('number DESC')
    end

    @pagy, @issues = pagy_countless(scope)
    fresh_when @issues, public: true
  end

  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    @issue = @repository.issues.find_by!(number: params[:id])
    fresh_when @issue, public: true
  end

  def labels
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:id].downcase)
    @labels = @repository.issues.pluck(:labels).flatten.compact.tally.sort_by { |_k, v| -v }
    expires_in 1.day, public: true
  end
end