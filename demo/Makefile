.DEFAULT_GOAL := help

ARGO_HOST ?= argo.dev.home
LOFT_HOST ?= loft.dev.home

bold := $(shell tput bold)
done := $(shell tput sgr0)
prompt := $(shell tput setaf 6) # cyan
value := $(shell tput setaf 7) # white

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'


start-demo: connected-clusters external-secrets argocd loft ## Start the demo environment, that is deploy argocd, external secrets, and available "connected clusters" (vclusters) and finally, loft.



# "connected clusters"

connected-clusters-deploy: ## Deploys "connected clusters" (vclusters) for use with argo and loft
	helm upgrade --install cluster-1 vcluster-k0s \
		--namespace cluster-1 --create-namespace \
		--repo https://charts.loft.sh \
		--values bootstrap/connected_clusters_1_values.yaml
	helm upgrade --install cluster-2 vcluster-k0s \
		--namespace cluster-2 --create-namespace \
		--repo https://charts.loft.sh \
		--values bootstrap/connected_clusters_2_values.yaml

.connected-clusters-wait-secrets: ## Wait for the "connected clusters" (and the secret that gets created) to be ready
	kubectl wait --namespace cluster-1 --for=condition=ready pod --selector=statefulset.kubernetes.io/pod-name=cluster-1-0 --timeout=120s
	kubectl wait --namespace cluster-2 --for=condition=ready pod --selector=statefulset.kubernetes.io/pod-name=cluster-2-0 --timeout=120s

connected-clusters: connected-clusters-deploy .connected-clusters-wait-secrets ## Deploy "connected clusters" (vclusters) and wait for the apiserver secrets to be ready


# external secrets

external-secrets-deploy: ## Installs external-secrets controller in the cluster
	helm upgrade --install external-secrets external-secrets/external-secrets \
		--namespace external-secrets --create-namespace \
		--set installCRDs=true

.external-secrets-wait: ## Wait for the external secrets controller to be ready
	kubectl wait --namespace external-secrets --for=condition=ready pod --selector=app.kubernetes.io/name=external-secrets-webhook --timeout=240s

# spagehetti here does the following:
# 	- ensure loft/argocd namespaces since we create the secrets in the respective places
#	- fetch the cluster secrets and assign them to temp envvars -- we have to do this prior to piping so the owning process
#     	has them set and they propogate along the way
# 		- do some yq magic to dump the cluster secret into the fake secret provider (yq here because sed dislikes multiline string in replace value)
#		- sed to replace CLUSTER1-CA-DATA, CLUSTER1-KEY-DATA and CLUSTER1-CERT-DATA with values from the vcluster secret
#	 	- rinse and repeat for cluster-2
#	- pass that to kubectl apply
external-secrets-deploy-fake: ## Setup the fake external secrets provider
	@kubectl create namespace loft > /dev/null 2>&1 || true
	@kubectl create namespace argocd > /dev/null 2>&1 || true
	@export TMPCLUSTER1=$$(kubectl get secrets --namespace cluster-1  vc-cluster-1 -o jsonpath='{.data.config}' | base64 -d) && \
		export TMPCLUSTER2=$$(kubectl get secrets --namespace cluster-2  vc-cluster-2 -o jsonpath='{.data.config}' | base64 -d) && \
		cat bootstrap/external_secrets.yaml | \
		yq e 'select(.kind == "ClusterSecretStore").spec.provider.fake.data[1].value |= strenv(TMPCLUSTER1)' | \
		sed "s|CLUSTER1-CA-DATA|$$(printenv TMPCLUSTER1 | yq .clusters[0].cluster.certificate-authority-data)|" | \
		sed "s|CLUSTER1-KEY-DATA|$$(printenv TMPCLUSTER1 | yq .users[0].user.client-key-data)|" | \
		sed "s|CLUSTER1-CERT-DATA|$$(printenv TMPCLUSTER1 | yq .users[0].user.client-certificate-data)|" | \
		yq e 'select(.kind == "ClusterSecretStore").spec.provider.fake.data[2].value |= strenv(TMPCLUSTER2)' | \
		sed "s|CLUSTER2-CA-DATA|$$(printenv TMPCLUSTER2 | yq .clusters[0].cluster.certificate-authority-data)|" | \
		sed "s|CLUSTER2-KEY-DATA|$$(printenv TMPCLUSTER2 | yq .users[0].user.client-key-data)|" | \
		sed "s|CLUSTER2-CERT-DATA|$$(printenv TMPCLUSTER2 | yq .users[0].user.client-certificate-data)|" | \
		kubectl apply -f -

external-secrets: external-secrets-deploy .external-secrets-wait external-secrets-deploy-fake ## Setup external-secrets and wait for it to be ready


# argocd

argocd-deploy: ## Deploy argocd in the current kube context
	@echo "kubectl create namespace argocd" $$(kubectl create namespace argocd 2>/dev/null || true)
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

.argocd-wait: ## Wait for the argocd server to be ready
	kubectl wait --namespace argocd --for=condition=ready pod --selector=app.kubernetes.io/name=argocd-server --timeout=120s

argocd-create-repository: ## Create an argocd repository pointing to this projects git remote
	cat bootstrap/argocd_repo.yaml | sed -E "s|(url:).*|\1 $$(git remote get-url origin| tr -d '\n' | base64)|" | kubectl apply -f -

argocd: argocd-deploy .argocd-wait argocd-create-repository

.argocd-get-admin-password: ## Fetch the argocd default admin password
	@printf "$(bold)$(prompt)%30s$(done) $(bold)$(value)%s$(done)\n" "argocd admin password:" "$$(kubectl --namespace argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo)"


# loft

loft-create-application: ## Create the loft application to install/manage loft in the argocd cluster; uses latest (including dev unless STABLE envvar set!) chart version
	cat bootstrap/argocd_loft_application.yaml | \
		sed "s|REPO_URL|$$(git remote get-url origin)|" | \
		sed "s|INGRESS_HOST|$(LOFT_HOST)|" | \
		kubectl apply -f -

.loft-wait: ## Wait for the loft deployment to be ready
	while ! kubectl get namespace loft ; do sleep 1 ; done
	while ! kubectl get --namespace loft pod | grep loft ; do sleep 1 ; done
	kubectl wait --namespace loft --for=condition=ready pod --selector=app=loft --timeout=120s

loft: loft-create-application .loft-wait ## Creates the loft application

.loft-get-admin-password: ## Fetch the loft default admin password
	@printf "$(bold)$(prompt)%30s$(done) $(bold)$(value)%s$(done)\n" "loft admin password:" "$$(./helper/loft-get-admin-password.sh)"


# port-forward

.argocd-port-forward: ## Use port-forwarding to expose argocd server on localhost:8080
	@kubectl port-forward --namespace argocd svc/argocd-server 8080:443 > /dev/null 2>&1 &
	@printf "$(bold)$(prompt)%30s$(done) $(bold)$(value)%s$(done)\n" "argocd exposed at:" "https://localhost:8080"

argocd-port-forward: .argocd-get-admin-password .argocd-port-forward ## Fetches the argocd admin password and starts port forwarding for argocd

stop-port-forward-argocd: ## Stop port-forwarding for argocd
	@kill $$(ps aux | grep '[k]ubectl port-forward --namespace argocd svc/argocd-server 8080:443' | awk '{print $$2}') || true

.loft-port-forward: ## Use port-forwarding to expose loft server on localhost:8081
	@kubectl port-forward --namespace loft svc/loft 8081:443 > /dev/null 2>&1 &
	@printf "$(bold)$(prompt)%30s$(done) $(bold)$(value)%s$(done)\n" "loft exposed at:" "https://localhost:8081"

loft-port-forward: .loft-get-admin-password .loft-port-forward ## Fetches the loft admin password and starts port forwarding for loft

stop-port-forward-loft: ## Stop port-forwarding for loft
	@kill $$(ps aux | grep '[k]ubectl port-forward --namespace loft svc/loft 8081:443' | awk '{print $$2}') || true

port-forward: argocd-port-forward loft-port-forward ## Start port-forwarding for arcod and loft

stop-port-forward: stop-port-forward-argocd stop-port-forward-loft ## Stop port-forwarding for argocd and loft


# ingress

.argocd-ingress: ## Setup an ingress for argocd
	@cat bootstrap/argocd_ingress.yaml | \
	sed "s|INGRESS_HOST|$(ARGO_HOST)|" | \
	kubectl apply -f -  > /dev/null 2>&1 &
	@printf "$(bold)$(prompt)%30s$(done) $(bold)$(value)%s$(done)\n" "argocd exposed at:" "https://$(ARGO_HOST)"

argocd-ingress: .argocd-get-admin-password .argocd-ingress ## Fetches the argocd admin password and setups an ingress for argocd

argocd-delete-ingress: ## Delete the argocd ingress
	kubectl delete --namespace argocd ingress argo-ingress

.loft-ingress: ## Setup an ingress for argocd
	@cat bootstrap/loft_ingress.yaml | \
	sed "s|INGRESS_HOST|$(LOFT_HOST)|" | \
	kubectl apply -f - > /dev/null 2>&1 &
	@printf "$(bold)$(prompt)%30s$(done) $(bold)$(value)%s$(done)\n" "loft exposed at:" "https://$(LOFT_HOST)"

loft-ingress: .loft-get-admin-password .loft-ingress ## Fetches the loft admin password and setups an ingress for loft

loft-delete-ingress: ## Delete the loft ingress
	kubectl delete --namespace loft ingress loft-ingress

setup-ingresses: argocd-ingress loft-ingress ## Setup argo and loft ingresses

delete-ingresses: argocd-delete-ingress loft-delete-ingress ## Deletes argo and loft ingresses

