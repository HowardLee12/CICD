# Multi-Environment CI/CD Deployment Guide

本專案已升級為支援多環境的 CI/CD 部署流程，包含 Development、Staging 和 Production 三個環境。

## 📁 專案結構

```
.
├── .github/workflows/          # GitHub Actions workflows
│   ├── ci.yml                 # 統一的 CI pipeline
│   ├── deploy-dev.yml         # Development 環境部署
│   ├── deploy-staging.yml     # Staging 環境部署
│   └── deploy-production.yml  # Production 環境部署
├── environments/              # 環境配置文件
│   ├── dev/
│   │   ├── ecs-task-def.json  # Development ECS 任務定義
│   │   └── env.yaml           # Development 環境變數
│   ├── staging/
│   │   ├── ecs-task-def.json  # Staging ECS 任務定義
│   │   └── env.yaml           # Staging 環境變數
│   └── production/
│       ├── ecs-task-def.json  # Production ECS 任務定義
│       └── env.yaml           # Production 環境變數
├── scripts/                   # 部署腳本
│   ├── build.sh              # Docker 構建腳本
│   └── deploy.sh             # 部署腳本
├── docker-compose.yml         # 本地開發環境
└── app/                       # 應用程式碼
```

## 🚀 部署流程

### 自動部署觸發條件

1. **Development 環境**
   - 觸發條件：推送到 `feature/**`, `develop`, `hotfix/**` 分支
   - 部署目標：`howard-ecs-cluster-dev`
   - 鏡像標籤：`dev-{branch-name}-{commit-hash}`

2. **Staging 環境**
   - 觸發條件：推送到 `main` 分支
   - 部署目標：`howard-ecs-cluster-staging`
   - 鏡像標籤：`staging-{commit-hash}`

3. **Production 環境**
   - 觸發條件：推送 tag `v*` 或手動觸發
   - 部署目標：`howard-ecs-cluster-prod`
   - 鏡像標籤：版本標籤 (例如 `v1.2.3`)
   - 需要手動審核和批准

## 🛠️ 本地開發

### 設置腳本權限

```bash
chmod +x scripts/build.sh
chmod +x scripts/deploy.sh
```

### 使用 Docker Compose 進行本地開發

```bash
# 啟動開發環境
docker-compose --profile dev up -d

# 查看日誌
docker-compose logs -f app-dev

# 停止開發環境
docker-compose --profile dev down

# 啟動 staging 環境進行本地測試
docker-compose --profile staging up -d
```

### 本地構建和測試

```bash
# 構建開發環境鏡像
./scripts/build.sh -e dev

# 構建並推送到 ECR
./scripts/build.sh -e dev -p

# 使用自定義標籤構建
./scripts/build.sh -t my-feature-v1.0
```

## 📋 手動部署

### 使用部署腳本

```bash
# 部署到開發環境
./scripts/deploy.sh -e dev

# 部署特定版本到 staging
./scripts/deploy.sh -e staging -t staging-abc123

# 部署到生產環境
./scripts/deploy.sh -e production -t v1.2.3

# 乾運行（測試部署腳本但不實際部署）
./scripts/deploy.sh -e dev -d
```

## 🏗️ AWS 基礎設施要求

### ECS 集群和服務

需要為每個環境創建對應的 AWS 資源：

**Development:**
- ECS 集群：`howard-ecs-cluster-dev`
- ECS 服務：`howard-ecs-service-dev`
- CloudWatch 日誌組：`/ecs/howard-task-dev`

**Staging:**
- ECS 集群：`howard-ecs-cluster-staging`
- ECS 服務：`howard-ecs-service-staging`
- CloudWatch 日誌組：`/ecs/howard-task-staging`

**Production:**
- ECS 集群：`howard-ecs-cluster-prod`
- ECS 服務：`howard-ecs-service-prod`
- CloudWatch 日誌組：`/ecs/howard-task-prod`

### IAM 角色

確保以下 IAM 角色存在且具有適當權限：
- `GitHubActionsPushToECR` - 推送鏡像到 ECR
- `GitHubActionsDeployToECS` - 部署到 ECS
- `ecsTaskExecutionRole` - ECS 任務執行角色

## 🔄 GitFlow 工作流程

### 功能開發

```bash
# 1. 創建功能分支
git checkout -b feature/new-api-endpoint

# 2. 開發和提交
git add .
git commit -m "Add new API endpoint"

# 3. 推送分支（自動觸發 dev 部署）
git push origin feature/new-api-endpoint

# 4. 創建 Pull Request 到 main
```

### 發佈到 Staging

```bash
# 1. 合併功能分支到 main
git checkout main
git merge feature/new-api-endpoint

# 2. 推送到 main（自動觸發 staging 部署）
git push origin main
```

### 發佈到 Production

```bash
# 1. 創建版本標籤
git tag -a v1.2.3 -m "Release version 1.2.3"

# 2. 推送標籤（觸發 production 部署）
git push origin v1.2.3

# 3. 在 GitHub Actions 中審核和批准部署
```

## 🔍 監控和日誌

### CloudWatch 日誌

每個環境的日誌都會自動發送到對應的 CloudWatch 日誌組：
- Development: `/ecs/howard-task-dev`
- Staging: `/ecs/howard-task-staging`
- Production: `/ecs/howard-task-prod`

### 健康檢查

所有環境都配置了健康檢查端點：
- Development: `https://dev.yourapp.com/health`
- Staging: `https://staging.yourapp.com/health`
- Production: `https://yourapp.com/health`

## 🛡️ 安全性和最佳實踐

### 環境隔離
- 每個環境使用獨立的 AWS 資源
- 不同的 IAM 角色和權限
- 獨立的日誌和監控

### 部署安全
- Production 環境需要手動審核
- 所有部署都經過健康檢查
- 自動回滾機制（ECS 服務穩定性檢查）

### 配置管理
- 環境變數通過 ECS 任務定義管理
- 敏感資料應使用 AWS Secrets Manager
- 配置文件版本控制

## 🔧 故障排除

### 常見問題

1. **部署失敗**
   ```bash
   # 檢查 ECS 服務狀態
   aws ecs describe-services --cluster howard-ecs-cluster-dev --services howard-ecs-service-dev
   
   # 查看任務日誌
   aws logs get-log-events --log-group-name /ecs/howard-task-dev --log-stream-name [stream-name]
   ```

2. **鏡像推送失敗**
   ```bash
   # 重新登錄 ECR
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 640168440704.dkr.ecr.us-east-1.amazonaws.com
   ```

3. **健康檢查失敗**
   ```bash
   # 手動測試健康檢查端點
   curl -f https://dev.yourapp.com/health
   ```

### 日誌查看

```bash
# 查看 GitHub Actions 日誌
# 前往 GitHub -> Actions tab -> 選擇對應的 workflow

# 查看 ECS 任務日誌
aws logs tail /ecs/howard-task-dev --follow

# 查看本地容器日誌
docker-compose logs -f app-dev
```

## 📚 相關文檔

- [AWS ECS 文檔](https://docs.aws.amazon.com/ecs/)
- [GitHub Actions 文檔](https://docs.github.com/en/actions)
- [Docker 文檔](https://docs.docker.com/)
- [ECR 文檔](https://docs.aws.amazon.com/ecr/)

## 🤝 貢獻指南

1. 確保所有功能分支都經過 dev 環境測試
2. 合併到 main 前確保 staging 環境穩定
3. 生產部署需要 code review 和手動批准
4. 遵循語義化版本控制 (Semantic Versioning)

---

**重要提醒：** 在使用此多環境部署系統之前，請確保已在 AWS 中創建所需的 ECS 集群、服務和相關資源。如需協助設置 AWS 基礎設施，請參考 `environments/` 目錄下的配置文件。
