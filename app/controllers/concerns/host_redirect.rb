module HostRedirect
  extend ActiveSupport::Concern

  private

  def find_host_with_redirect(host_name)
    # Try to find exact match first
    host = Host.find_by(name: host_name)
    
    # If not found, try case-insensitive search
    unless host
      host = Host.find_by('LOWER(name) = ?', host_name.downcase)
      
      # If found with different case, redirect to correct case
      if host && host.name != host_name
        # Special case for repositories index - redirect to host show
        if params[:controller].end_with?('repositories') && params[:action] == 'index'
          redirect_path = is_api_controller? ? api_v1_host_path(host.name) : host_path(host.name)
          redirect_to redirect_path, status: :moved_permanently
        else
          redirect_to url_for(params.permit!.merge(host_id: host.name)), status: :moved_permanently
        end
        return host
      end
    end
    
    # If still not found, raise error
    raise ActiveRecord::RecordNotFound.new("Couldn't find Host with name=#{host_name}") unless host
    
    host
  end

  def is_api_controller?
    self.class.name.start_with?('Api::')
  end
end