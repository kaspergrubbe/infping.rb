NS ?= kaspergrubbe
IMAGE_NAME ?= infping-rb
VERSION ?= latest

compose-rebuild:
	docker-compose build --force-rm --no-cache

compose-clean:
	docker-compose down --remove-orphans

run:
	docker-compose up

run-local:
	DEBUG=1 INFLUXDB_ENDPOINT=http://localhost:8086 INFLUXDB_BUCKET=infping_rb_testing INFLUXDB_TOKEN=UPXO41QetOqRzS7Sj8Lo448YRg2GXXTyki0e5j0tjr78COqzBYDduP8v2sinMcVCwCOLK3b7IfUh6X5LNMjE6Q== INFLUXDB_ORG=blarghco HOSTS=1.1.1.1,8.8.8.8 ruby infping.rb

build:
	docker build --compress --no-cache --file Dockerfile --tag $(NS)/$(IMAGE_NAME):$(VERSION) .

push:
	docker push $(NS)/$(IMAGE_NAME):$(VERSION)

release:
	make build
	make push
	git tag -a v$(VERSION) -m 'Tagging for release: $(VERSION)'
	git push origin v$(VERSION)

default: build
