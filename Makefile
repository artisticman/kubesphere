# Copyright 2018 The KubeSphere Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License 
# described in the file LICENSE.
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The binary to build 
BIN ?= ks-apiserver

# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif


IMG ?= kubespheredev/ks-apiserver
OUTPUT_DIR=bin
GOFLAGS=-mod=vendor
define ALL_HELP_INFO
# Build code.
#
# Args:
#   WHAT: Directory names to build.  If any of these directories has a 'main'
#     package, the build will produce executable files under $(OUT_DIR).
#     If not specified, "everything" will be built.
#   GOFLAGS: Extra flags to pass to 'go' when building.
#   GOLDFLAGS: Extra linking flags passed to 'go' when building.
#   GOGCFLAGS: Additional go compile flags passed to 'go' when building.
#
# Example:
#   make
#   make all
#   make all WHAT=cmd/ks-apiserver
#     Note: Use the -N -l options to disable compiler optimizations an inlining.
#           Using these build options allows you to subsequently use source
#           debugging tools like delve.
endef
.PHONY: all
all: test hypersphere ks-apiserver ks-apigateway ks-iam controller-manager

# Build ks-apiserver binary
ks-apiserver: fmt vet
	hack/gobuild.sh cmd/ks-apiserver

# Build ks-apigateway binary
ks-apigateway: fmt vet
	hack/gobuild.sh cmd/ks-apigateway

# Build ks-iam binary
ks-iam: fmt vet
	hack/gobuild.sh cmd/ks-iam

# Build controller-manager binary
controller-manager: fmt vet
	hack/gobuild.sh cmd/controller-manager

# Build hypersphere binary
hypersphere: fmt vet
	hack/gobuild.sh cmd/hypersphere

# Run go fmt against code 
fmt: generate
	gofmt -w ./pkg ./cmd ./tools ./api

# Run go vet against code
vet: generate
	go vet ./pkg/... ./cmd/...

# Generate manifests e.g. CRD, RBAC etc.
manifests:
	go run ./vendor/sigs.k8s.io/controller-tools/cmd/controller-gen/main.go all

deploy: manifests
	kubectl apply -f config/crds
	kustomize build config/default | kubectl apply -f -

# generate will generate crds' deepcopy & go openapi structs
# Futher more about go:genreate . https://blog.golang.org/generate
generate:
	go generate ./pkg/... ./cmd/...

deepcopy:
	GO111MODULE=on go install -mod=vendor k8s.io/code-generator/cmd/deepcopy-gen
	${GOPATH}/bin/deepcopy-gen -i kubesphere.io/kubesphere/pkg/apis/... -h ./hack/boilerplate.go.txt -O zz_generated.deepcopy

openapi:
	go run ./vendor/k8s.io/kube-openapi/cmd/openapi-gen/openapi-gen.go -O openapi_generated -i ./vendor/k8s.io/apimachinery/pkg/apis/meta/v1,./pkg/apis/tenant/v1alpha1 -p kubesphere.io/kubesphere/pkg/apis/tenant/v1alpha1 -h ./hack/boilerplate.go.txt --report-filename ./api/api-rules/violation_exceptions.list
	go run ./vendor/k8s.io/kube-openapi/cmd/openapi-gen/openapi-gen.go -O openapi_generated -i ./vendor/k8s.io/apimachinery/pkg/apis/meta/v1,./pkg/apis/servicemesh/v1alpha2 -p kubesphere.io/kubesphere/pkg/apis/servicemesh/v1alpha2 -h ./hack/boilerplate.go.txt --report-filename ./api/api-rules/violation_exceptions.list
	go run ./vendor/k8s.io/kube-openapi/cmd/openapi-gen/openapi-gen.go -O openapi_generated -i ./vendor/k8s.io/api/networking/v1,./vendor/k8s.io/apimachinery/pkg/apis/meta/v1,./pkg/apis/network/v1alpha1 -p kubesphere.io/kubesphere/pkg/apis/network/v1alpha1 -h ./hack/boilerplate.go.txt --report-filename ./api/api-rules/violation_exceptions.list
	go run ./vendor/k8s.io/kube-openapi/cmd/openapi-gen/openapi-gen.go -O openapi_generated -i ./vendor/k8s.io/apimachinery/pkg/apis/meta/v1,./pkg/apis/devops/v1alpha1 -p kubesphere.io/kubesphere/pkg/apis/devops/v1alpha1 -h ./hack/boilerplate.go.txt --report-filename ./api/api-rules/violation_exceptions.list
	go run ./tools/cmd/crd-doc-gen/main.go
# Build the docker image
docker-build: all
	docker build . -t ${IMG}

# Run tests
test: fmt vet
	export KUBEBUILDER_CONTROLPLANE_START_TIMEOUT=1m; go test ./pkg/... ./cmd/... -covermode=atomic -coverprofile=coverage.txt

.PHONY: clean
clean:
	-make -C ./pkg/version clean
	@echo "ok"

# find or download controller-gen
# download controller-gen if necessary
clientset: 
	./hack/generate_client.sh


# Currently in the upgrade phase of controller tools.
# But the new controller tools are not compatible with the old version.
# With these commands you may need to manually modify the generated code
# So don't use it unless you know it very deeply
internal-crds:
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./pkg/apis/network/..." output:crd:artifacts:config=config/crd/bases

internal-generate-apis: internal-controller-gen
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/network/...

internal-controller-gen:
ifeq (, $(shell which controller-gen))
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.0-beta.4
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

network-rbac:
	$(CONTROLLER_GEN) paths=./pkg/controller/network/provider/ paths=./pkg/controller/network/ rbac:roleName=network-manager output:rbac:artifacts:config=kustomize/network/calico-k8s
	$(CONTROLLER_GEN) paths=./pkg/controller/network/ rbac:roleName=network-manager output:rbac:artifacts:config=kustomize/network/calico-etcd
