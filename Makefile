.DEFAULT_GOAL := help

ifdef DEVEL
CHARTVERSION := $(shell helm search repo loft/loft --versions --devel -o json | jq '.[0].version')
else
CHARTVERSION := $(shell helm search repo loft/loft --versions -o json | jq '.[0].version')
endif

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

loft-update-chart-versions: ## Updates the loft and loft-agent chart dependency versions, set DEVEL envvar to prefer latest development version to stable version
	helm repo update
	sed -i ".bak" -r -E "s|(  version:).*|\1 $(CHARTVERSION)|" loft/Chart.yaml
	@rm loft/Chart.yaml.bak
	sed -i ".bak" -r -E "s|(  version:).*|\1 $(CHARTVERSION)|" loft-agent/Chart.yaml
	@rm loft-agent/Chart.yaml.bak
	cd loft; helm dependency update .
