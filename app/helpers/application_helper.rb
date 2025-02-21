module ApplicationHelper
  include Pagy::Frontend

  def meta_title
    [@meta_title, 'Ecosyste.ms: Issues'].compact.join(' | ')
  end

  def meta_description
    @meta_description || app_description
  end

  def app_name
    "Issues"
  end

  def app_description
    'An open API service for providing issue and pull request metadata for open source projects.'
  end

  def obfusticate_email(email)
    return unless email    
    email.split('@').map do |part|
      begin
        part.tap { |p| p[1...-1] = "****" }
      rescue
        '****'
      end
    end.join('@')
  end

  def distance_of_time_in_words_if_present(time)
    return 'N/A' unless time
    distance_of_time_in_words(time)
  end

  def rounded_number_with_delimiter(number)
    return 0 unless number
    number_with_delimiter(number.round(2))
  end

  def bot?(author)
    return false unless author
    author.ends_with?('[bot]')
  end

  def render_chart(name, max: @max, ytitle: nil)
    content_tag :div, class: 'chart-container py-4 my-4' do
      line_chart chart_data_host_repository_path(@repository.host, @repository, chart: name, period: @period, exclude_bots: @exclude_bots, start_date: @start_date, end_date: @end_date), thousands: ",", title: name.humanize, max: max, ytitle: ytitle
    end
  end
end
