.PHONY: lint fmt test ci dev-up dev-down elixir-spec test-integration

bin/ameba: bin/ameba.cr
	crystal build -o bin/ameba bin/ameba.cr

lint: bin/ameba
	bin/ameba

fmt:
	crystal tool format src
	crystal tool format spec
	crystal tool format spec-integration

test:
	crystal spec --error-trace


dev-up:
	docker-compose up -d

dev-down:
	docker-compose down -v

elixir-spec: dev-up
	docker-compose exec elixir-spec.dev sh

test-integration: dev-up
	docker-compose run --rm -e LOG_LEVEL=debug crystal-spec.dev crystal spec --error-trace spec-integration

ci: lint fmt test test-integration
	echo 'done'
