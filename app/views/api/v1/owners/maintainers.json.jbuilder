json.login @owner

json.maintainers @maintainers do |maintainer, count|
  json.maintainer maintainer
  json.count count
  json.url api_v1_host_author_url(@host, maintainer)
end
json.active_maintainers @active_maintainers do |maintainer, count|
  json.maintainer maintainer
  json.count count
  json.url api_v1_host_author_url(@host, maintainer)
end