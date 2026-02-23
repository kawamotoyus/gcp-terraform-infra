# ハンズオン作業記録

後から内容を振り返れるよう、実際に実行したコマンドや設定した内容を記録します。

## Step 1 & 2: 準備とGCPプロジェクト作成
- （ブラウザ操作等で）GCPプロジェクト `gcp-lab-488301` を作成し、課金設定とAPI有効化を実施

## Step 3: ローカル環境でのTerraform初期設定とGCP認証
1. **Terraform基本設定の作成**
   - `versions.tf` に利用するプロバイダ（Google）のバージョンを指定
   - `provider.tf` にデプロイ対象のプロジェクトIDとリージョン（`asia-northeast1`）を指定
2. **gcloud (GCP CLI) のインストールと認証**
   - ローカルPC（Dev Container）に `gcloud` コマンドをインストールし、PATHを通す
   - `gcloud auth application-default login` を実行し、ブラウザ経由でGCPへのアクセス権限（Application Default Credentials）を取得
   - `gcloud auth application-default set-quota-project gcp-lab-488301` を実行し、API利用時の課金・制限枠として自身のプロジェクトを紐付け

## Step 4: Terraform stateファイルの管理基盤の作成 (進行中)
Terraformの実行状態（tfstateファイル）を保存するため、GCS（Cloud Storage）バケットを作成します。

```bash
# gcloudコマンド操作のデフォルトプロジェクトを指定
gcloud config set project gcp-lab-488301

# GCSバケットの作成（アクセス制御をプロジェクト全体のものに統一）
gcloud storage buckets create gs://terraform-state-gcp-lab-488301 \
  --location=asia-northeast1 \
  --uniform-bucket-level-access
```

### TerraformのBackend設定と初期化
作成したGCSバケットを「状態管理ファイル（tfstate）」の保存先として利用するよう、`versions.tf` に `backend "gcs"` のブロックを追記しました。
その後、各種プロバイダプラグインのダウンロードとBackendの接続確認を兼ねて初期化コマンドを実行します。

```bash
cd /workspaces/AGLabo/GCP/terraform
terraform init
```

## Step 5: Workload Identity (OIDC) の構築
GitHub ActionsからGCPへの安全なキーレス認証を実現するため、`iam.tf` に以下のリソースを定義しました。
- `google_iam_workload_identity_pool`: 認証の受付窓口
- `google_iam_workload_identity_pool_provider`: OIDCプロバイダ設定（対象リポジトリを `kawamotoyus/gcp-terraform-infra` に限定）
- `google_service_account`: CI/CD実行用の一時的なサービスアカウント
- `google_service_account_iam_member`: 上記の窓口とサービスアカウントの紐付け

```bash
cd /workspaces/AGLabo/GCP/terraform
terraform apply
```

## Step 6: Terraform Cloud Runリソースの定義
Webサーバー（Nginx）をCloud Runで起動し、インターネットへ公開するためのTerraformコード（`cloudrun.tf`）を作成しました。
また、GitHub Actions（サービスアカウント）がこのリソースを作成できるように、`iam.tf` に必要な権限（`roles/run.admin` および `roles/iam.securityAdmin`）を追記しました。

※ ここではローカルから `terraform apply` を行わず、Step 7のCI/CDパイプラインを使って自動デプロイをテストします。

## Step 7: GitHub Actionsワークフローの設定と自動デプロイ
OIDCを利用してGCPにアクセスし、自動でTerraformを実行するCI/CDの仕組みを `.github/workflows/deploy.yml` に定義しました。
ローカルの変更をすべてコミットし、GitHubの `main` ブランチにプッシュすることで自動デプロイが開始されます。

```bash
git add .
git commit -m "feat: complete terraform and github actions setup"
git push origin main
```

### 🚨 トラブルシューティング（GitHub Actions実行時のエラー）

**エラー1: `IAM Service Account Credentials API has not been used...`**
- **原因:** GitHub ActionsがOIDCを利用してGCPのサービスアカウントになりすます（権限を借りる）ためのAPIが、GCPプロジェクト上で無効になっていた。
- **対処:** 以下のコマンドをローカルで実行し、APIを有効化。
  ```bash
  gcloud services enable iamcredentials.googleapis.com --project gcp-lab-488301
  ```

**エラー2: `Permission 'storage.objects.list' denied on resource...`**
- **原因:** CI/CD用のサービスアカウント（`terraform-ci-sa`）に対し、「Cloud Runを作る権限」は与えていたが、Terraformの状態（tfstate）を保存している「GCSバケットを読み書きする権限」を与え忘れていたため、`terraform init` 時にステートのロック確認ができず失敗した。
- **対処:** `iam.tf` に `roles/storage.admin` の権限付与設定を追記。このIAM設定自体を反映するため、一度だけローカルから `terraform apply` を実行してGCPに適用した。

**エラー3: `Cloud Run Admin API has not been used...`**
- **原因:** GCP上で Cloud Run を作成・操作するための基本機能（API）が無効化されていたため。
- **対処:** 以下のコマンドをローカルで実行し、APIを有効化。（※実行前に目的と影響を確認済）
  ```bash
  gcloud services enable run.googleapis.com --project gcp-lab-488301
  ```

**エラー4: `Identity and Access Management (IAM) API has not been used...`**
- **原因:** GitHub ActionsからTerraformを実行した際、GCP上でIAMリソース（Workload Identity Pool等）を読み込み・確認するための基本APIが無効化されていたため。
- **対処:** 以下のコマンドをローカルで実行し、APIを有効化。（※実行前に目的と影響を確認済）
  ```bash
  gcloud services enable iam.googleapis.com --project gcp-lab-488301
  ```

**エラー5: `Permission 'iam.workloadIdentityPools.get' denied...`**
- **原因:** `terraform-ci-sa` に基本的なIAM変更権限（`securityAdmin`）はあったが、Workload Identityそのものやサービスアカウント自体の状態を確認する専門権限が不足していた。
- **対処:** `iam.tf` に `roles/iam.workloadIdentityPoolAdmin` および `roles/iam.serviceAccountAdmin` を追加し、ローカルから適用。

**エラー6: `Cloud Resource Manager API has not been used...`**
- **原因:** プロジェクトのIAM設定状況を確認する際に必要な Cloud Resource Manager API が無効化されていたため。
- **対処:** 以下のコマンドをローカルで実行し、APIを有効化。
  ```bash
  gcloud services enable cloudresourcemanager.googleapis.com --project gcp-lab-488301
  ```

**エラー8: `The user-provided container failed to start and listen on the port...`**
- **原因:** Cloud Runはデフォルトでコンテナに対し「`8080` 番ポートで通信を待ち受けてね」と指示を出すが、今回利用したDockerイメージ（`nginx:latest`）は「`80` 番ポート」で通信を待つ仕様になっており、ポートの不一致で起動確認に失敗した（タイムアウトした）ため。
- **対処:** `cloudrun.tf` に `ports { container_port = 80 }` ブロックを明示的に追記し、Nginxのポート指定と一致させた。

### おまけ：完全無料枠（Always Free）の適用について
Cloud Runの完全無料枠（毎月18万vCPU秒、36万GBメモリ秒、200万リクエスト）は、世界中のすべてのリージョンで適用されるわけではなく、**米国の特定リージョン（`us-central1`, `us-east1`, `us-west1`）のみ**が対象となる仕様がある。
日本リージョン（`asia-northeast1`）のままでもある程度の利用なら維持費・稼働費ともに実質0円に収まるが、より安全に「1円も課金させない設計」にするため、`cloudrun.tf` の `location` 設定を `us-central1`（アイオワ）に変更した。
