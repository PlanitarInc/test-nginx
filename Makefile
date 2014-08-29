.PHONY: build push clean test

export AWS_S3_BUCKET="iguide.plntr"
export AWS_ACCESS_KEY_ID="AKIAIYALDWSHG26NBB3A"
export AWS_SECRET_ACCESS_KEY="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"

ifneq (${NOCACHE},)
  NOCACHEFLAG=--no-cache
endif

build: bin/app static/big.txt
	docker build ${NOCACHEFLAG} -t planitar/test-nginx .

push:
	docker push planitar/test-nginx

clean:
	rm -rf ./bin
	rm -f static/big.txt
	docker rmi -f planitar/test-nginx 2> /dev/null || true

test: build
	docker run -d --name ng -p ::80 -p ::9000 \
	  -e "AWS_S3_BUCKET=${AWS_S3_BUCKET}" \
	  -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" \
	  -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" \
	  planitar/test-nginx
	sleep 5s
	/bin/bash -lc 'set -ex; \
	  NGINX_PORT=$$(docker inspect -f "{{ (index (index .NetworkSettings.Ports \"80/tcp\") 0).HostPort }}" ng); \
	  APP_PORT=$$(docker inspect -f "{{ (index (index .NetworkSettings.Ports \"9000/tcp\") 0).HostPort }}" ng); \
	  curl -f# http://${AWS_S3_BUCKET}.s3.amazonaws.com/small.txt >/dev/null; \
	  curl -f# http://localhost:$${APP_PORT}/small.txt >/dev/null; \
	  curl -f# http://localhost:$${APP_PORT}/view/small.txt >/dev/null; \
	  curl -f# http://localhost:$${NGINX_PORT}/ >/dev/null; \
	  curl -f# http://localhost:$${NGINX_PORT}/static/small.txt >/dev/null; \
	  curl -f# http://localhost:$${NGINX_PORT}/s3/small.txt >/dev/null; \
	  curl -f# http://localhost:$${NGINX_PORT}/app/small.txt >/dev/null; \
	  curl -f# http://localhost:$${NGINX_PORT}/app/view/small.txt >/dev/null; \
	  '; \
	if [ $$? -ne 0 ]; then \
	  docker logs ng | tail; \
	  docker rm -f ng; \
	  false; \
	fi
	docker rm -f ng

bin/app:
	mkdir -p bin
	docker run --rm -v `pwd`/bin:/out planitar/dev-go /bin/bash -lc ' \
	  sudo apt-get update && \
	  sudo apt-get install -y bzr && \
	  go get "github.com/PlanitarInc/test-nginx/app" && \
	  cp $$GOPATH/bin/app /out \
	'

static/big.txt: 
	@# Generate ~5MB ascii file
	cat /dev/urandom | tr -cd 'a-z0-9A-Z\n \t' | head -c 5242891 > $@
