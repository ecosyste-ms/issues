class IssuesController < ApplicationController
  def index
    @host = Host.find_by_name!(params[:host_id])
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    # TODO filters
    @pagy, @issues = pagy(@repository.issues.order('number DESC'))
    expires_in 1.hour, public: true
  end

end