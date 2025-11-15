.PHONY: help test test-unit test-integration test-e2e test-fast test-coverage test-auth test-servers test-search test-health test-core install-dev lint format check-deps clean build-keycloak push-keycloak build-and-push-keycloak deploy-keycloak update-keycloak

# Default target
help:
	@echo "🧪 MCP Registry Testing Commands"
	@echo ""
	@echo "Setup:"
	@echo "  install-dev     Install development dependencies"
	@echo "  check-deps      Check if test dependencies are installed"
	@echo ""
	@echo "Testing:"
	@echo "  test            Run full test suite with coverage"
	@echo "  test-unit       Run unit tests only"
	@echo "  test-integration Run integration tests only" 
	@echo "  test-e2e        Run end-to-end tests only"
	@echo "  test-fast       Run fast tests (exclude slow tests)"
	@echo "  test-coverage   Generate coverage reports"
	@echo ""
	@echo "Domain Testing:"
	@echo "  test-auth       Run authentication domain tests"
	@echo "  test-servers    Run server management domain tests"
	@echo "  test-search     Run search domain tests"
	@echo "  test-health     Run health monitoring domain tests"
	@echo "  test-core       Run core infrastructure tests"
	@echo ""
	@echo "Code Quality:"
	@echo "  lint            Run linting checks"
	@echo "  format          Format code"
	@echo "  clean           Clean up test artifacts"
	@echo ""
	@echo "Keycloak Build & Deploy:"
	@echo "  build-keycloak              Build Keycloak Docker image locally"
	@echo "  build-and-push-keycloak     Build and push to ECR"
	@echo "  deploy-keycloak             Update ECS service (after push)"
	@echo "  update-keycloak             Build, push, and deploy in one command"

# Installation
install-dev:
	@echo "📦 Installing development dependencies..."
	pip install -e .[dev]

check-deps:
	@python scripts/test.py check

# Full test suite
test:
	@python scripts/test.py full

# Test types
test-unit:
	@python scripts/test.py unit

test-integration:
	@python scripts/test.py integration

test-e2e:
	@python scripts/test.py e2e

test-fast:
	@python scripts/test.py fast

test-coverage:
	@python scripts/test.py coverage

# Domain-specific tests
test-auth:
	@python scripts/test.py auth

test-servers:
	@python scripts/test.py servers

test-search:
	@python scripts/test.py search

test-health:
	@python scripts/test.py health

test-core:
	@python scripts/test.py core

# Code quality
lint:
	@echo "🔍 Running linting checks..."
	@python -m bandit -r registry/ -f json || true
	@echo "✅ Linting complete"

format:
	@echo "🎨 Formatting code..."
	@python -m black registry/ tests/ --diff --color
	@echo "✅ Code formatting complete"

# Cleanup
clean:
	@echo "🧹 Cleaning up test artifacts..."
	@rm -rf htmlcov/
	@rm -rf tests/reports/
	@rm -rf .coverage
	@rm -rf coverage.xml
	@rm -rf .pytest_cache/
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "✅ Cleanup complete"

# Development workflow
dev-test: clean install-dev test-fast
	@echo "🚀 Development test cycle complete!"

# CI/CD workflow
ci-test: clean check-deps test test-coverage
	@echo "🏗️ CI/CD test cycle complete!"

# Keycloak Build & Deployment
# Variables
AWS_REGION ?= us-west-2
AWS_PROFILE ?= default
IMAGE_TAG ?= latest

build-keycloak:
	@echo "🐋 Building Keycloak Docker image..."
	docker build \
		-t keycloak:$(IMAGE_TAG) \
		-f docker/keycloak/Dockerfile \
		docker/keycloak
	@echo "✅ Image built: keycloak:$(IMAGE_TAG)"

build-and-push-keycloak:
	@echo "📦 Building and pushing Keycloak to ECR..."
	./scripts/build-and-push-keycloak.sh \
		--aws-region $(AWS_REGION) \
		--aws-profile $(AWS_PROFILE) \
		--image-tag $(IMAGE_TAG)
	@echo "✅ Keycloak image built and pushed successfully"

deploy-keycloak:
	@echo "🚀 Deploying Keycloak ECS service..."
	aws ecs update-service \
		--cluster keycloak \
		--service keycloak \
		--force-new-deployment \
		--region $(AWS_REGION) \
		--profile $(AWS_PROFILE) \
		--output table
	@echo "✅ ECS service update initiated"

update-keycloak: build-and-push-keycloak deploy-keycloak
	@echo ""
	@echo "✅ Keycloak update complete!"
	@echo ""
	@echo "Service URLs:"
	@echo "  Admin Console: https://kc.mycorp.click/admin"
	@echo "  Service URL:   https://kc.mycorp.click"
	@echo ""
	@echo "Monitor deployment:"
	@echo "  aws ecs describe-services --cluster keycloak --services keycloak --region $(AWS_REGION) --query 'services[0].[serviceName,status,runningCount,desiredCount]' --output table" 