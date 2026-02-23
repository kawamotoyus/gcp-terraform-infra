# GitHub Actions の設定で必要になる、Providerのフルネーム
output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github_provider.name
  description = "The Workload Identity Provider ID for GitHub Actions"
}

# CI/CDがGCPを操作する際の「顔」となるサービスアカウントのメールアドレス
output "service_account_email" {
  value       = google_service_account.github_actions.email
  description = "The Service Account email used by GitHub Actions"
}
