# Cloud Run v2サービスの定義
resource "google_cloud_run_v2_service" "hello_nginx" {
  name     = "hello-cloud-run"
  location = "asia-northeast1"
  project  = "gcp-lab-488301"

  template {
    containers {
      image = "nginx:latest"
      resources {
        limits = {
          cpu    = "1000m" # 1 vCPU
          memory = "256Mi"
        }
      }
    }
  }
}

# インターネットへの全公開（IAM）設定
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_v2_service_iam_policy" "noauth" {
  project     = google_cloud_run_v2_service.hello_nginx.project
  location    = google_cloud_run_v2_service.hello_nginx.location
  name        = google_cloud_run_v2_service.hello_nginx.name
  policy_data = data.google_iam_policy.noauth.policy_data
}
