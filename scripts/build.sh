#!/bin/bash

# build.sh - Multi-environment Docker build script
set -e

# Default values
ENVIRONMENT=""
TAG=""
PUSH=false
REGISTRY="640168440704.dkr.ecr.us-east-1.amazonaws.com"
REPOSITORY="howard-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [-e ENVIRONMENT] [-t TAG] [-p] [-h]"
    echo "  -e ENVIRONMENT  Target environment (dev, staging, production)"
    echo "  -t TAG         Custom tag for the image"
    echo "  -p             Push image to ECR after building"
    echo "  -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                              # Build with auto-generated tag"
    echo "  $0 -e dev                       # Build for dev environment"
    echo "  $0 -t v1.2.3                   # Build with custom tag"
    echo "  $0 -e staging -p                # Build for staging and push to ECR"
    echo "  $0 -t custom-feature -p         # Build with custom tag and push"
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

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

generate_tag() {
    if [ -n "$TAG" ]; then
        log "Using provided tag: $TAG"
        return
    fi
    
    # Get current git information
    local branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    if [ -n "$ENVIRONMENT" ]; then
        case $ENVIRONMENT in
            dev)
                TAG="dev-${branch_name//\//-}-${commit_hash}"
                ;;
            staging)
                TAG="staging-${commit_hash}"
                ;;
            production)
                if git describe --tags --exact-match HEAD 2>/dev/null; then
                    TAG=$(git describe --tags --exact-match HEAD)
                else
                    TAG="prod-${commit_hash}"
                fi
                ;;
        esac
    else
        # Auto-detect based on branch
        case $branch_name in
            main|master)
                TAG="staging-${commit_hash}"
                ENVIRONMENT="staging"
                ;;
            feature/*|develop|hotfix/*)
                TAG="dev-${branch_name//\//-}-${commit_hash}"
                ENVIRONMENT="dev"
                ;;
            *)
                TAG="custom-${branch_name//\//-}-${commit_hash}"
                ;;
        esac
    fi
    
    log "Generated tag: $TAG"
    if [ -n "$ENVIRONMENT" ]; then
        log "Detected environment: $ENVIRONMENT"
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running"
    fi
    
    log "Docker is available and running"
}

check_aws_credentials() {
    if [ "$PUSH" = true ]; then
        if ! aws sts get-caller-identity &>/dev/null; then
            error "AWS credentials not configured or expired (required for push)"
        fi
        log "AWS credentials validated"
    fi
}

build_image() {
    local full_image_name="$REPOSITORY:$TAG"
    
    log "Building Docker image..."
    debug "Image name: $full_image_name"
    debug "Build context: $(pwd)"
    
    # Check if Dockerfile exists
    if [ ! -f "Dockerfile" ]; then
        error "Dockerfile not found in current directory"
    fi
    
    # Build the image
    docker build \
        --tag "$full_image_name" \
        --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --build-arg VERSION="$TAG" \
        --build-arg ENVIRONMENT="$ENVIRONMENT" \
        .
    
    if [ $? -eq 0 ]; then
        log "✅ Image built successfully: $full_image_name"
    else
        error "❌ Image build failed"
    fi
    
    # Also tag with environment-latest if environment is specified
    if [ -n "$ENVIRONMENT" ]; then
        local env_latest_tag="$REPOSITORY:$ENVIRONMENT-latest"
        docker tag "$full_image_name" "$env_latest_tag"
        log "Tagged as: $env_latest_tag"
    fi
}

push_to_ecr() {
    if [ "$PUSH" != true ]; then
        log "Skipping push to ECR (use -p flag to enable)"
        return
    fi
    
    log "Pushing image to ECR..."
    
    # Login to ECR
    aws ecr get-login-password --region us-east-1 | \
        docker login --username AWS --password-stdin "$REGISTRY"
    
    if [ $? -ne 0 ]; then
        error "Failed to login to ECR"
    fi
    
    # Tag for ECR
    local local_image="$REPOSITORY:$TAG"
    local remote_image="$REGISTRY/$REPOSITORY:$TAG"
    
    docker tag "$local_image" "$remote_image"
    
    # Push the image
    docker push "$remote_image"
    
    if [ $? -eq 0 ]; then
        log "✅ Image pushed successfully: $remote_image"
    else
        error "❌ Failed to push image to ECR"
    fi
    
    # Push environment-latest tag if applicable
    if [ -n "$ENVIRONMENT" ]; then
        local env_latest_local="$REPOSITORY:$ENVIRONMENT-latest"
        local env_latest_remote="$REGISTRY/$REPOSITORY:$ENVIRONMENT-latest"
        
        docker tag "$env_latest_local" "$env_latest_remote"
        docker push "$env_latest_remote"
        
        if [ $? -eq 0 ]; then
            log "✅ Environment latest tag pushed: $env_latest_remote"
        else
            warn "⚠️ Failed to push environment latest tag"
        fi
    fi
}

show_summary() {
    echo ""
    log "🏗️ BUILD SUMMARY"
    echo "=================="
    echo "Tag: $TAG"
    if [ -n "$ENVIRONMENT" ]; then
        echo "Environment: $ENVIRONMENT"
    fi
    echo "Local image: $REPOSITORY:$TAG"
    if [ "$PUSH" = true ]; then
        echo "Remote image: $REGISTRY/$REPOSITORY:$TAG"
    fi
    echo ""
    
    if [ "$PUSH" = true ]; then
        log "🚀 Image is ready for deployment!"
        if [ -n "$ENVIRONMENT" ]; then
            log "💡 To deploy: ./scripts/deploy.sh -e $ENVIRONMENT -t $TAG"
        fi
    else
        log "📦 Image built locally"
        log "💡 To push: $0 -t $TAG -p"
        if [ -n "$ENVIRONMENT" ]; then
            log "💡 To build and push: $0 -e $ENVIRONMENT -p"
        fi
    fi
}

main() {
    log "Starting Docker build process..."
    
    check_docker
    generate_tag
    check_aws_credentials
    build_image
    push_to_ecr
    show_summary
}

# Parse command line arguments
while getopts "e:t:ph" opt; do
    case $opt in
        e)
            ENVIRONMENT="$OPTARG"
            ;;
        t)
            TAG="$OPTARG"
            ;;
        p)
            PUSH=true
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

# Run main function
main
