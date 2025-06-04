#!/bin/bash

# deploy.sh - Multi-environment deployment script
set -e

# Default values
ENVIRONMENT=""
IMAGE_TAG=""
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 -e ENVIRONMENT [-t IMAGE_TAG] [-d]"
    echo "  -e ENVIRONMENT  Target environment (dev, staging, production)"
    echo "  -t IMAGE_TAG    Docker image tag (optional, defaults to latest for env)"
    echo "  -d              Dry run mode"
    echo ""
    echo "Examples:"
    echo "  $0 -e dev                           # Deploy latest dev image"
    echo "  $0 -e staging -t staging-abc123     # Deploy specific staging image"
    echo "  $0 -e production -t v1.2.3          # Deploy production with tag v1.2.3"
    echo "  $0 -e dev -d                        # Dry run for dev environment"
    exit 1
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

validate_environment() {
    case $ENVIRONMENT in
        dev|staging|production)
            log "Environment: $ENVIRONMENT"
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or production"
            ;;
    esac
}

set_default_image_tag() {
    if [ -z "$IMAGE_TAG" ]; then
        case $ENVIRONMENT in
            dev)
                IMAGE_TAG="dev-latest"
                ;;
            staging)
                IMAGE_TAG="staging-latest"
                ;;
            production)
                IMAGE_TAG="production-latest"
                ;;
        esac
    fi
    log "Image tag: $IMAGE_TAG"
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &>/dev/null; then
        error "AWS credentials not configured or expired"
    fi
    log "AWS credentials validated"
}

check_image_exists() {
    log "Checking if image exists in ECR..."
    if ! aws ecr describe-images \
        --repository-name howard-test \
        --image-ids imageTag=$IMAGE_TAG \
        --region us-east-1 &>/dev/null; then
        error "Image with tag $IMAGE_TAG not found in ECR"
    fi
    log "Image found in ECR"
}

update_task_definition() {
    local task_def_file="environments/$ENVIRONMENT/ecs-task-def.json"
    local temp_file="/tmp/ecs-task-def-$ENVIRONMENT.json"
    
    if [ ! -f "$task_def_file" ]; then
        error "Task definition file not found: $task_def_file"
    fi
    
    log "Updating task definition with image tag: $IMAGE_TAG"
    
    # Update the image in task definition
    sed "s|640168440704.dkr.ecr.us-east-1.amazonaws.com/howard-test:.*\"|640168440704.dkr.ecr.us-east-1.amazonaws.com/howard-test:$IMAGE_TAG\"|" \
        "$task_def_file" > "$temp_file"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would use task definition:"
        cat "$temp_file"
    else
        cp "$temp_file" "$task_def_file"
        log "Task definition updated"
    fi
}

deploy_to_ecs() {
    local cluster_name
    local service_name
    local task_def_file="environments/$ENVIRONMENT/ecs-task-def.json"
    
    case $ENVIRONMENT in
        dev)
            cluster_name="howard-ecs-cluster-dev"
            service_name="howard-ecs-service-dev"
            ;;
        staging)
            cluster_name="howard-ecs-cluster-staging"
            service_name="howard-ecs-service-staging"
            ;;
        production)
            cluster_name="howard-ecs-cluster-prod"
            service_name="howard-ecs-service-prod"
            ;;
    esac
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would deploy to:"
        log "  Cluster: $cluster_name"
        log "  Service: $service_name"
        log "  Task Definition: $task_def_file"
        return
    fi
    
    log "Deploying to ECS..."
    log "  Environment: $ENVIRONMENT"
    log "  Cluster: $cluster_name"
    log "  Service: $service_name"
    
    # Register new task definition
    TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file://$task_def_file \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    if [ $? -ne 0 ]; then
        error "Failed to register task definition"
    fi
    
    log "Task definition registered: $TASK_DEF_ARN"
    
    # Update service
    aws ecs update-service \
        --cluster $cluster_name \
        --service $service_name \
        --task-definition $TASK_DEF_ARN \
        --force-new-deployment
    
    if [ $? -ne 0 ]; then
        error "Failed to update ECS service"
    fi
    
    log "Service update initiated"
    
    # Wait for deployment to complete
    log "Waiting for service to stabilize..."
    aws ecs wait services-stable \
        --cluster $cluster_name \
        --services $service_name
    
    if [ $? -eq 0 ]; then
        log "✅ Deployment completed successfully!"
    else
        error "❌ Deployment failed or timed out"
    fi
}

run_health_checks() {
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would run health checks"
        return
    fi
    
    local health_url
    case $ENVIRONMENT in
        dev)
            health_url="https://dev.yourapp.com/health"
            ;;
        staging)
            health_url="https://staging.yourapp.com/health"
            ;;
        production)
            health_url="https://yourapp.com/health"
            ;;
    esac
    
    log "Running health checks..."
    log "Health check URL: $health_url"
    
    # Wait a bit for the service to be ready
    sleep 30
    
    # Try health check up to 5 times
    for i in {1..5}; do
        if curl -f -s "$health_url" > /dev/null; then
            log "✅ Health check passed!"
            return 0
        else
            warn "Health check attempt $i failed, retrying in 10 seconds..."
            sleep 10
        fi
    done
    
    error "❌ Health checks failed after 5 attempts"
}

main() {
    log "Starting deployment process..."
    
    validate_environment
    set_default_image_tag
    check_aws_credentials
    check_image_exists
    update_task_definition
    deploy_to_ecs
    run_health_checks
    
    if [ "$DRY_RUN" = true ]; then
        log "🔍 DRY RUN COMPLETED - No actual deployment performed"
    else
        log "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
        case $ENVIRONMENT in
            dev)
                log "🌐 Application URL: https://dev.yourapp.com"
                ;;
            staging)
                log "🌐 Application URL: https://staging.yourapp.com"
                ;;
            production)
                log "🌐 Application URL: https://yourapp.com"
                ;;
        esac
    fi
}

# Parse command line arguments
while getopts "e:t:dh" opt; do
    case $opt in
        e)
            ENVIRONMENT="$OPTARG"
            ;;
        t)
            IMAGE_TAG="$OPTARG"
            ;;
        d)
            DRY_RUN=true
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$ENVIRONMENT" ]; then
    error "Environment is required. Use -e option."
fi

# Run main function
main
