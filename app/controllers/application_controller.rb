class ApplicationController < ActionController::Base
  include Pagy::Backend

  skip_before_action :verify_authenticity_token

  after_action lambda {
    request.session_options[:skip] = true
  }

   def debug
    render plain: [
      "request.ssl?: #{request.ssl?}",
      "X-Forwarded-Proto: #{request.headers['X-Forwarded-Proto']}",
      "X-Forwarded-Ssl: #{request.headers['X-Forwarded-Ssl']}",
      "request.scheme: #{request.scheme}",
      "request.protocol: #{request.protocol}"
    ].join("\n")
  end
end
