#!/bin/sh

FILE="$1"

report() {
  echo "#### $1"
  echo ''
  echo '```shell'
  echo "$ ab -c 1 -n 1000 $2"
  ab -c 1 -n 1000 "$2"
  echo '```'
  echo ''
}

if [ -z "$FILE" -o -z "$NGINX_PORT" -o -z "$APP_PORT" -o -z "$AWS_S3_BUCKET" ]; then
  [ -z "$NGINX_PORT" ] && echo "Error: Set NGINX_PORT env var" >&2
  [ -z "$APP_PORT" ] && echo "Error: Set APP_PORT env var" >&2
  [ -z "$AWS_S3_BUCKET" ] && echo "Error: Set AWS_S3_BUCKET env var" >&2
  [ -z "$FILE" ] && echo "Error: Provide filename in arguments" >&2
  exit 1
fi

echo FILE: $FILE
echo NGINX_PORT: $NGINX_PORT
echo APP_PORT: $APP_PORT
echo AWS_S3_BUCKET: $AWS_S3_BUCKET
curl -v http://localhost:${NGINX_PORT}/static/${FILE}

if ! curl -sf http://localhost:${NGINX_PORT}/static/${FILE}; then
  echo "Error: cannot access 'http://localhost:${NGINX_PORT}/static/${FILE}'" >&2
  exit 1
fi

echo ''
echo "## Benchmark results for $FILE"
echo ''

report 'Nginx statix' http://localhost:${NGINX_PORT}/static/${FILE}
report 'Nginx S3' http://localhost:${NGINX_PORT}/s3/${FILE}
report 'Nginx app static' http://localhost:${NGINX_PORT}/app/${FILE}
report 'Nginx app S3' http://localhost:${NGINX_PORT}/app/view/${FILE}
report 'App static' http://localhost:${APP_PORT}/${FILE}
report 'App S3' http://localhost:${APP_PORT}/view/${FILE}
report 'S3' http://${AWS_S3_BUCKET}.s3.amazonaws.com/${FILE}
