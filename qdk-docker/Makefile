USERNAME=qeekdev
NAME=qdk-docker
VERSION=2.3.4

IMAGE=$(USERNAME)/$(NAME)

all: docker-build

docker-build:
	git submodule update --init QDK
	docker build -t $(IMAGE):$(VERSION)-buildstage -f ./Dockerfile.build-stage .
	docker build -t $(IMAGE):$(VERSION)-apim -f ./Dockerfile.run-time .

docker-run:
	docker run -ti --rm --name "qdk-docker" $(IMAGE):$(VERSION)-apim /bin/bash
