# Convenience wrapper. Requires: terraform, gcloud, kubectl.
# Override on the command line, e.g.  make creds PROJECT=my-proj ZONE=us-central1-a

PROJECT ?= $(shell cd terraform && terraform output -raw 2>/dev/null; true)
CLUSTER ?= vrising
ZONE    ?= us-central1-a
POOL    ?= game
NS      ?= vrising

.PHONY: help tf-init tf-plan tf-apply tf-destroy creds deploy secret logs status ip scale-up scale-down

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

tf-init: ## terraform init
	cd terraform && terraform init

tf-plan: ## terraform plan
	cd terraform && terraform plan

tf-apply: ## terraform apply
	cd terraform && terraform apply

tf-destroy: ## tear down all infra (world-save disk is retained)
	cd terraform && terraform destroy

creds: ## fetch kubectl credentials for the cluster
	gcloud container clusters get-credentials $(CLUSTER) --zone $(ZONE) --project $(PROJECT)

secret: ## create the K8s Secret interactively (prompts for passwords)
	@read -p "Server password (blank = public): " sp; \
	 read -p "RCON password: " rp; \
	 kubectl -n $(NS) create secret generic vrising-secrets \
	   $${sp:+--from-literal=HOST_SETTINGS_Password=$$sp} \
	   --from-literal=HOST_SETTINGS_Rcon__Password=$$rp \
	   --dry-run=client -o yaml | kubectl apply -f -

deploy: ## apply the GKE overlay
	kubectl apply -k k8s/overlays/gke

status: ## show pods, pvcs, service
	kubectl -n $(NS) get pods,pvc,svc

logs: ## tail the server log
	kubectl -n $(NS) logs -f statefulset/vrising

ip: ## show the external LoadBalancer IP
	kubectl -n $(NS) get svc vrising -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'

scale-up: ## manually resize the node pool to 1
	gcloud container clusters resize $(CLUSTER) --node-pool $(POOL) --zone $(ZONE) --num-nodes 1 --quiet

scale-down: ## manually resize the node pool to 0
	gcloud container clusters resize $(CLUSTER) --node-pool $(POOL) --zone $(ZONE) --num-nodes 0 --quiet
