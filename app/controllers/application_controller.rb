class ApplicationController < ActionController::Base
  include Pagy::Backend

  skip_before_action :verify_authenticity_token
  before_action :set_cache_headers

  after_action lambda {
    request.session_options[:skip] = true
  }

  def find_host
    find_host_by_param(:host_id)
  end

  def find_host_by_id
    find_host_by_param(:id)
  end

  def find_host_by_param(param_name)
    host_param = params[param_name]
    @host = Host.find_by_name!(host_param)
    unless @host.name == host_param
      safe_params = request.query_parameters.except(:controller, :action, :host, :port, :protocol)
      redirect_params = safe_params.merge(param_name => @host.name)
      redirect_to url_for(redirect_params.merge(only_path: true)), status: :moved_permanently
    end
  end

  def sanitize_sort(allowed_columns, default: 'updated_at')
    sort_param = params[:sort].presence || default
    sql = allowed_columns[sort_param] || allowed_columns[default] || default
    Arel.sql(sql)
  end

  def set_cache_headers(browser_ttl: 5.minutes, cdn_ttl: 6.hours)
    return unless request.get?
    response.cache_control.merge!(
      public: true,
      max_age: browser_ttl.to_i,
      stale_while_revalidate: cdn_ttl.to_i,
      stale_if_error: 1.day.to_i
    )
    response.cache_control[:extras] = ["s-maxage=#{cdn_ttl.to_i}"]
  end
end
