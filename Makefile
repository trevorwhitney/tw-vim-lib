.PHONY: help docker

help:
	@echo "Available targets:"
	@echo "  docker  - Build the Claude Docker image"

docker:
	docker build -t tw-claude-code:latest -f lua/tw/claude/docker/Dockerfile lua/tw/claude/docker
