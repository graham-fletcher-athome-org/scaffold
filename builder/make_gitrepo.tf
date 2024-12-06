

resource "github_repository" "repo" {
  count = var.uri == null ? 1 : 0
  name        = var.name
  visibility = "private"
}

locals{
    git_uri = var.uri == null ? format("%s.git",github_repository.repo[0].html_url) : var.uri
}
