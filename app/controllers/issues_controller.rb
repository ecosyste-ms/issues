class IssuesController < ApplicationController
  include HostRedirect
  
  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    
    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)
    # TODO filters
    @pagy, @issues = pagy(@repository.issues.order('number DESC'))
    expires_in 1.hour, public: true
  end

end