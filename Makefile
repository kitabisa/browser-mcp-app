SHELL                 = /bin/bash

APP_NAME              = browser-mcp-app
VERSION               = $(shell git describe --always --tags)
GIT_COMMIT            = $(shell git rev-parse HEAD)
GIT_DIRTY             = $(shell test -n "`git status --porcelain`" && echo "+CHANGES" || true)
LATEST_TAG            = $(shell [[ "${ENV_NAME}" = "stg" || "${ENV_NAME}" = "prod" ]] && echo "latest" || echo "latest-${ENV_NAME}")
SQUAD                 = backend
BUSINESS              = platform
PLATFORM              = backend
ENTITY                = kitabisa

.PHONY: default
default: help

.PHONY: help
help:
	@echo 'Management commands for ${APP_NAME}:'
	@echo
	@echo 'Usage:'
	@echo '    make package                            Build, tag, and push Docker image.'
	@echo '    make deploy                             Deploy to Kubernetes via Helmfile.'
	@echo '    make deploy-reload-config               Deploy config tier via Helmfile.'
	@echo '    make rollback RELEASE= REVISION=        Rollback via Helm. If REVISION is omitted, it will roll back to the previous release.'
	@echo '    make helm-history-length                Get the number of Helm revisions.'
	@echo '    make helm-oldest-revision               Get the oldest Helm revision.'
	@echo '    make helm-image-tag REVISION=           Get the image tag for a Helm revision.'
	@echo '    make prune IMAGE_TAG=                   Remove a Docker image from GCR.'
	@echo '    make get-app-name                       Print the application name.'
	@echo '    make get-business-unit                  Print the business unit.'
	@echo '    make destroy                            Uninstall all helm release'
	@echo

.PHONY: package
package:
	@echo "Build, tag, and push Docker image ${APP_NAME} ${VERSION} ${GIT_COMMIT}"
	docker buildx build \
		--build-arg VERSION=${VERSION} \
		--build-arg GIT_COMMIT=${GIT_COMMIT}${GIT_DIRTY} \
		--cache-from type=local,src=/tmp/.buildx-cache \
		--cache-to type=local,dest=/tmp/.buildx-cache \
		--tag ${DOCKER_REPOSITORY}/${APP_NAME}:${GIT_COMMIT} \
		--tag ${DOCKER_REPOSITORY}/${APP_NAME}:${VERSION} \
		--tag ${DOCKER_REPOSITORY}/${APP_NAME}:${VERSION}-${ENV_NAME} \
		--tag ${DOCKER_REPOSITORY}/${APP_NAME}:${LATEST_TAG} \
		--push .

.PHONY: deploy
deploy:
	@echo "Deploying ${APP_NAME} ${VERSION}"
	export APP_NAME=${APP_NAME} && \
	export VERSION=${VERSION} && \
	export SQUAD=${SQUAD} && \
	export BUSINESS=${BUSINESS} && \
	export PLATFORM=${PLATFORM} && \
	export ENTITY=${ENTITY} && \
	helmfile apply

.PHONY: deploy-reload-config
deploy-reload-config:
	@echo "Deploying ${APP_NAME} ${VERSION}"
	export APP_NAME=${APP_NAME} && \
	export VERSION=${VERSION} && \
	export SQUAD=${SQUAD} && \
	export BUSINESS=${BUSINESS} && \
	export PLATFORM=${PLATFORM} && \
	export ENTITY=${ENTITY} && \
	helmfile --selector tier=config apply

.PHONY: helm-history-length
helm-history-length:
	@helm history \
		--namespace ${APP_NAME} \
		--output yaml \
		${APP_NAME}-server-${ENV_NAME} | yq r - --length

.PHONY: helm-oldest-revision
helm-oldest-revision:
	@helm history \
		--namespace ${APP_NAME} \
		--output yaml \
		${APP_NAME}-server-${ENV_NAME} | yq r - "[0]".revision

.PHONY: helm-image-tag
helm-image-tag:
	@helm get values \
		--namespace ${APP_NAME} \
		--revision ${REVISION} \
		--output yaml \
		${APP_NAME}-server-${ENV_NAME} | yq r - image.tag

.PHONY: prune
prune:
	@echo "Removing Docker image ${DOCKER_REPOSITORY}/${APP_NAME}:${IMAGE_TAG}"
	gcloud container images delete \
		--force-delete-tags \
		--quiet \
		${DOCKER_REPOSITORY}/${APP_NAME}:${IMAGE_TAG}

.PHONY: rollback
rollback:
	@echo "Rollback ${RELEASE} ${REVISION}"
	helm rollback \
		--namespace ${APP_NAME} \
		${RELEASE} ${REVISION}

.PHONY: get-app-name
get-app-name:
	@echo ${APP_NAME}

.PHONY: get-business-unit
get-business-unit:
	@echo ${BUSINESS}

.PHONY: destroy
destroy:
	@echo "Destroying ${APP_NAME} ${ENV_NAME}"
	helm list \
		--namespace ${APP_NAME} \
		--filter ${ENV_NAME} \
		--output yaml | \
	yq eval '.[].name' - | \
	xargs helm uninstall --namespace ${APP_NAME}
