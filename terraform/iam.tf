# 1. CI/CDが利用するサービスアカウントの作成
resource "google_service_account" "github_actions" {
  project      = "gcp-lab-488301"
  account_id   = "terraform-ci-sa"
  display_name = "GitHub Actions Service Account for Terraform"
  description  = "Service account for GitHub Actions to manage GCP resources via Terraform"
}

# 2. Workload Identity Pool の作成（身分証の受付窓口）
resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = "gcp-lab-488301"
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Identity pool for GitHub Actions OIDC"
}

# 3. Workload Identity Pool Provider の作成（確認手順と許可条件）
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = "gcp-lab-488301"
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions Provider"

  # GitHubのOIDCトークンを発行するURL
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # GitHub側の情報（sub, repository等）をGCP側の属性（attribute）にマッピングする
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  # セキュリティの要：このリポジトリからのアクセスしか絶対に許可しない
  attribute_condition = "assertion.repository == 'kawamotoyus/gcp-terraform-infra'"
}

# 4. Service Account と Workload Identity の紐付け
# 「この窓口を通ってきた特定のリポジトリ（あなた）に、このSAを使わせる」という許可
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"

  # pool_id を使って、このPoolを経由してきて、かつ指定の属性を満たすユーザーに許可を与える
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/kawamotoyus/gcp-terraform-infra"
}

# 5. Cloud Run を作成・管理するための権限をCI/CDサービスアカウントに付与
resource "google_project_iam_member" "cloud_run_admin" {
  project = "gcp-lab-488301"
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# 6. IAM全般やセキュリティ設定を管理するための権限を付与
resource "google_project_iam_member" "security_admin" {
  project = "gcp-lab-488301"
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# (追加) 6-2. CI/CD自身がWorkload Identityを管理（読み取り含む）するための権限
resource "google_project_iam_member" "workload_identity_admin" {
  project = "gcp-lab-488301"
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# (追加) 6-3. CI/CD自身がサービスアカウントを管理（読み取り含む）するための権限
resource "google_project_iam_member" "service_account_admin" {
  project = "gcp-lab-488301"
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# 7. Terraformのステート管理（GCSバケット）にアクセスするための権限をCI/CDサービスアカウントに付与
resource "google_project_iam_member" "storage_admin" {
  project = "gcp-lab-488301"
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
