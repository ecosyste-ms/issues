json.extract! host, :name, :url, :kind, :last_synced_at, :repositories_count, :issues_count, :pull_requests_count, :icon_url
json.host_url api_v1_host_url(host)
json.repositories_url api_v1_host_repositories_url(host)