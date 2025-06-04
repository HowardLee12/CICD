#!/bin/bash

# setup-multi-env.sh - 設置多環境部署的初始化腳本
set -e

echo "🚀 Setting up Multi-Environment CI/CD Deployment"
echo "================================================"

# 檢查必要的工具
check_tools() {
    echo "📋 Checking required tools..."
    
    for tool in aws docker git; do
        if ! command -v $tool &> /dev/null; then
            echo "❌ $tool is not installed"
            exit 1
        else
            echo "✅ $tool is available"
        fi
    done
}

# 設置腳本權限
setup_permissions() {
    echo "🔐 Setting up script permissions..."
    chmod +x scripts/build.sh
    chmod +x scripts/deploy.sh
    echo "✅ Script permissions set"
}

# 驗證 AWS 配置
check_aws() {
    echo "☁️ Checking AWS configuration..."
    
    if ! aws sts get-caller-identity &>/dev/null; then
        echo "❌ AWS credentials not configured"
        echo "Please run: aws configure"
        exit 1
    fi
    
    echo "✅ AWS credentials configured"
    
    # 檢查 ECR 倉庫
    if ! aws ecr describe-repositories --repository-names howard-test --region us-east-1 &>/dev/null; then
        echo "⚠️ ECR repository 'howard-test' not found"
        echo "Creating ECR repository..."
        aws ecr create-repository --repository-name howard-test --region us-east-1
        echo "✅ ECR repository created"
    else
        echo "✅ ECR repository exists"
    fi
}

# 創建示例配置
create_example_configs() {
    echo "📁 Creating example configurations..."
    
    # 如果沒有 .env.example，創建一個
    if [ ! -f ".env.example" ]; then
        cat > .env.example << EOF
# Environment Configuration Example
ENVIRONMENT=development
LOG_LEVEL=DEBUG
PORT=8080

# Database (if needed)
DATABASE_URL=postgresql://user:password@localhost:5432/myapp

# Redis (if needed)
REDIS_URL=redis://localhost:6379

# AWS Configuration
AWS_REGION=us-east-1
EOF
        echo "✅ Created .env.example"
    fi
}

# 顯示後續步驟
show_next_steps() {
    echo ""
    echo "🎉 Multi-Environment CI/CD setup completed!"
    echo "=========================================="
    echo ""
    echo "📝 Next steps:"
    echo "1. Review and update the environment configurations in environments/ directory"
    echo "2. Create AWS ECS clusters and services for each environment:"
    echo "   - howard-ecs-cluster-dev / howard-ecs-service-dev"
    echo "   - howard-ecs-cluster-staging / howard-ecs-service-staging"
    echo "   - howard-ecs-cluster-prod / howard-ecs-service-prod"
    echo ""
    echo "3. Set up GitHub Environments in your repository:"
    echo "   - Go to Settings -> Environments"
    echo "   - Create: development, staging, production"
    echo "   - Configure protection rules for production"
    echo ""
    echo "4. Test the setup:"
    echo "   - Local build: ./scripts/build.sh -e dev"
    echo "   - Local deployment: ./scripts/deploy.sh -e dev -d"
    echo ""
    echo "5. Review the documentation:"
    echo "   - README_MULTI_ENV.md for detailed usage"
    echo "   - environments/ for environment-specific configurations"
    echo ""
    echo "🚀 Happy deploying!"
}

# 主函數
main() {
    check_tools
    setup_permissions
    check_aws
    create_example_configs
    show_next_steps
}

# 執行主函數
main
