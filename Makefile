UPSTREAM_TAG   ?= main
BUILD_VERSION  ?= local
IMAGE          ?= shelfmark-rootless:$(UPSTREAM_TAG)

.DEFAULT_GOAL := help

.PHONY: help build push run shell smoke clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

build: ## Build the image (UPSTREAM_TAG=main)
	docker build \
		--build-arg UPSTREAM_TAG=$(UPSTREAM_TAG) \
		--build-arg BUILD_VERSION=$(BUILD_VERSION) \
		-t $(IMAGE) \
		.

clean: ## Remove the locally built image
	docker rmi $(IMAGE) 2>/dev/null || true
