# Cloud Run v2サービスの定義
resource "google_cloud_run_v2_service" "hello_nginx" {
  name     = "hello-cloud-run"
  location = "us-central1" # 完全無料枠（Always Free）の対象リージョン
  project  = "gcp-lab-488301"

  template {
    containers {
      image = "nginx:latest"
      
      # Nginxはデフォルトで「80番」ポートを待ち受けるため明示的に指定
      ports {
        container_port = 80
      }

      resources {
        limits = {
          cpu    = "1000m" # 1 vCPU
          memory = "512Mi" # 最小要件
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
