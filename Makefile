help: ## Ask for help!
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

export

SIMPLE_STORAGE_BINARY := $(shell stack exec -- which simple-storage)

build-docs-local: ## Build the haddocks documentation for just this project (no dependencies)
	stack haddock --no-haddock-deps

install: ## Runs stack install to compile library and counter example app
	stack install

hlint: ## Run hlint on all haskell projects
	stack exec hlint -- -h .hlint.yaml hs-abci-server hs-abci-example hs-abci-extra

test: install ## Run the haskell test suite for all haskell projects
	stack test

deploy-simple-storage: install ## run the simple storage docker network
	BINARY_PATH=$(SIMPLE_STORAGE_BINARY) \
	docker-compose -f hs-abci-example/docker-compose.yaml up --build -d

run-simple-storage: install ## Run the example simple-storage app
	stack exec -- simple-storage

stylish: ## Run stylish-haskell over all haskell projects
	find ./hs-abci-server -name "*.hs" | xargs stack exec stylish-haskell -- -c ./.stylish_haskell.yaml -i
	find ./hs-abci-example -name "*.hs" | xargs stack exec stylish-haskell -- -c ./.stylish_haskell.yaml -i
	find ./hs-abci-extra -name "*.hs" | xargs stack exec stylish-haskell -- -c ./.stylish_haskell.yaml -i
