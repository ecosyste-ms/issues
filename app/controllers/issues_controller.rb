class IssuesController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    # TODO filters
    @pagy, @issues = pagy(@repository.issues.order('number DESC'))
  end

  def dependabot
    @host = Host.find_by_name!('GitHub')
    scope = @host.issues.dependabot.order('number DESC').includes(:repository)
    scope = scope.ecosystem(params[:ecosystem]) if params[:ecosystem].present?
    scope = scope.package_name(params[:package_name]) if params[:package_name].present?
    @pagy, @issues = pagy(scope)
  end
end