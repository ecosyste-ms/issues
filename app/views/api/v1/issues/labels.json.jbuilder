json.array! @labels do |label, count|
  json.label label
  json.count count
  json.issues_url api_v1_host_repository_issues_url(@host, @repository, label: label)
end
