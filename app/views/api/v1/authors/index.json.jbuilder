json.array! @authors do |author, count|
  json.login author
  json.repositories_count count
  json.author_url api_v1_host_author_url(@host, author)
end