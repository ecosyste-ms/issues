class Api::V1::IssuesController < Api::V1::ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    
    scope = @repository.issues

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'number'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('number DESC')
    end

    @pagy, @issues = pagy_countless(scope)
  end

  def show
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    @issue = @repository.issues.find_by!(number: params[:id])
  end
end