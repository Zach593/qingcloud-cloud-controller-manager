# tab space is 4
# GitHub viewer defaults to 8, change with ?ts=4 in URL

# Vars describing project
NAME= qingcloud-cloud-controller-manager
GIT_REPOSITORY= github.com/yunify/qingcloud-cloud-controller-manager
IMG?= kubespheredev/cloud-controller-manager:v1.3.3

# Generate vars to be included from external script
# Allows using bash to generate complex vars, such as project versions
GENERATE_VERSION_INFO_SCRIPT	= ./generate_version.sh
GENERATE_VERSION_INFO_OUTPUT	= version_info

# Define newline needed for subsitution to allow evaluating multiline script output
define newline


endef

# Call the version_info script with keyvalue option and evaluate the output
# Will import the keyvalue pairs and make available as Makefile variables
# Use dummy variable to only have execute once
$(eval $(subst #,$(newline),$(shell $(GENERATE_VERSION_INFO_SCRIPT) keyvalue | tr '\n' '#')))
# Call the verson_info script with json option and store result into output file and variable
# Will only execute once due to ':='
#GENERATE_VERSION_INFO			:= $(shell $(GENERATE_VERSION_INFO_SCRIPT) json | tee $(GENERATE_VERSION_INFO_OUTPUT))

# Set defaults for needed vars in case version_info script did not set
# Revision set to number of commits ahead
VERSION							?= 0.0
COMMITS							?= 0
REVISION						?= $(COMMITS)
BUILD_LABEL						?= unknown_build
BUILD_DATE						?= $(shell date -u +%Y%m%d.%H%M%S)
GIT_SHA1						?= unknown_sha1

IMAGE_LABLE         ?= $(BUILD_LABEL)
# Vars for export ; generate list of ENV vars based on matching export prefix
# Use strip to get rid of excessive spaces due to the foreach / filter / if logic
EXPORT_VAR_PREFIX               = EXPORT_VAR_
EXPORT_VARS                     = $(strip $(foreach v,$(filter $(EXPORT_VAR_PREFIX)%,$(.VARIABLES)),$(if $(filter environment%,$(origin $(v))),$(v))))

# Vars for go phase
# All vars which being with prefix will be included in ldflags
# Defaulting to full static build
GO_VARIABLE_PREFIX				= GO_VAR_
GO_VAR_BUILD_LABEL				:= $(BUILD_LABEL)
GO_VAR_VERSION                  := $(VERSION)
GO_VAR_GIT_SHA1                 := $(GIT_SHA1)
GO_VAR_BUILD_LABEL              := $(BUILD_LABEL)
GO_LDFLAGS						= $(foreach v,$(filter $(GO_VARIABLE_PREFIX)%, $(.VARIABLES)),-X github.com/yunify/qingcloud-cloud-controller-manager/qingcloud.$(patsubst $(GO_VARIABLE_PREFIX)%,%,$(v))=$(value $(value v)))
GO_BUILD_FLAGS					= -a -tags netgo -installsuffix nocgo -ldflags "$(GO_LDFLAGS)"

#src
qingcloud-cloud-controller-manager_pkg = $(subst $(GIT_REPOSITORY)/,,$(shell go list -f '{{ join .Deps "\n" }}' $(GIT_REPOSITORY) | grep "^$(GIT_REPOSITORY)" |grep -v "^$(GIT_REPOSITORY)/vendor/" ))
qingcloud-cloud-controller-manager_pkg += .

# default just build binary
default							: go-build

# target for debugging / printing variables
print-%							:
								@echo '$*=$($*)'

# perform go build on project
go-build						: bin/qingcloud-cloud-controller-manager

bin/qingcloud-cloud-controller-manager                     : $(foreach dir,$(qingcloud-cloud-controller-manager_pkg),$(wildcard $(dir)/*.go)) Makefile
								go build -o bin/qingcloud-cloud-controller-manager $(GO_BUILD_FLAGS) $(GIT_REPOSITORY) ./cmd/go

bin/.docker-images-build-timestamp                         : bin/qingcloud-cloud-controller-manager Makefile Dockerfile
								docker build -q -t $(DOCKER_IMAGE_NAME):$(IMAGE_LABLE) -t dockerhub.qingcloud.com/$(DOCKER_IMAGE_NAME):$(IMAGE_LABLE) . > bin/.docker-images-build-timestamp

bin/.docker_label               : bin/.docker-images-build-timestamp
								docker push $(DOCKER_IMAGE_NAME):$(IMAGE_LABLE)
								docker push dockerhub.qingcloud.com/$(DOCKER_IMAGE_NAME):$(IMAGE_LABLE)
								echo $(DOCKER_IMAGE_NAME):$(IMAGE_LABLE) > bin/.docker_label

install-docker                  : bin/.docker_label

publish                         : 
								CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-w" -o bin/manager ./cmd/main.go
								docker build -t ${IMG}  -f deploy/Dockerfile bin/
								docker push ${IMG}
clean                           :
								rm -rf bin/ && if -f bin/.docker-images-build-timestamp then docker rmi `cat bin/.docker-images-build-timestamp`
test                            : fmt vet
								go test -v -cover -mod=vendor ./pkg/...
fmt								:
								go fmt ./pkg/... ./cmd/... ./test/pkg/...
vet:
								go vet ./pkg/... ./cmd/... ./test/pkg/...

debug:
								./hack/debug.sh
								
.PHONY							: default all go-build clean install-docker test

e2e:
								./hack/e2e.sh