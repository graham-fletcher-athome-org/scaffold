/* Create service account for builder*/
resource "google_service_account" "builder_service_account" {
  account_id = var.name
  project    = var.managed_environment.builder_project
}

/*Create buckets for logging and to hold state files.  Give correct permissions */
module "logbucket_names" {
  source          = "../nameing_conventions/bucket_name"
  name            = format("log-%s", var.name)
  foundation_code = var.managed_environment.foundation_code
}

resource "google_storage_bucket" "log_buckets" {
  name                        = module.logbucket_names.name
  location                    = coalesce(var.location_log_buckets, var.managed_environment.default_location)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  project                     = var.managed_environment.builder_project
  force_destroy               = true
  public_access_prevention    = "enforced"
}

resource "google_storage_bucket_iam_member" "log_bucket_iam" {
  bucket = google_storage_bucket.log_buckets.id
  role   = "roles/storage.admin"
  member = format("serviceAccount:%s", google_service_account.builder_service_account.email)
}

module "build_assets_bucket_names" {
  source          = "../nameing_conventions/bucket_name"
  name            = format("ba-%s", var.name)
  foundation_code = var.managed_environment.foundation_code
}

resource "google_storage_bucket" "build_assets_buckets" {
  name                        = module.build_assets_bucket_names.name
  location                    = coalesce(var.location_ba_buckets, var.managed_environment.default_location)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  project                     = var.managed_environment.builder_project
  force_destroy               = true
  public_access_prevention    = "enforced"
}

resource "google_storage_bucket_iam_member" "build_assets_buckets_iam" {
  bucket = google_storage_bucket.build_assets_buckets.id
  role   = "roles/storage.objectUser"
  member = format("serviceAccount:%s", google_service_account.builder_service_account.email)
}

/* Make trigger and connect to github */
resource "google_cloudbuildv2_repository" "github_repos" {
  count             = var.managed_environment.git_hub_enabled ? 1 : 0
  project           = var.managed_environment.builder_project
  location          = coalesce(var.managed_environment.location_build_triggers, var.managed_environment.default_location)
  name              = var.name
  parent_connection = var.managed_environment.git_hub_connection
  remote_uri        = local.git_uri
}

# add any additional substitutions to the default list. Defaults will replace any duplicates
locals {
  default_trigger_substitutions = {
    _LOGBUCKET        = google_storage_bucket.log_buckets.id
    _BABUCKET         = google_storage_bucket.build_assets_buckets.id
    _DEFAULT_LOCATION = var.managed_environment.default_location
    _PLACES           = jsonencode(var.managed_environment.places)
    _FOUNDATION_CODE  = var.managed_environment.foundation_code
  }
  trigger_substitutions = merge(var.substitutions, local.default_trigger_substitutions)
}

resource "google_cloudbuild_trigger" "triggers" {
  count           = var.managed_environment.git_hub_enabled ? 1 : 0
  name            = var.name
  location        = coalesce(var.managed_environment.location_build_triggers, var.managed_environment.default_location)
  project         = var.managed_environment.builder_project
  service_account = google_service_account.builder_service_account.id
  ignored_files   = var.ignored_files
  included_files  = var.included_files
  repository_event_config {
    repository = google_cloudbuildv2_repository.github_repos[0].id
    push {
      branch = var.branch
    }
  }

  substitutions = local.trigger_substitutions

  filename           = var.file_name
  include_build_logs = "INCLUDE_BUILD_LOGS_WITH_STATUS"
}


