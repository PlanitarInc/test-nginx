To run:

```shell
AWS_S3_BUCKET="iguide.plntr"
docker run -d --name ng -p 8080:80 -p 9000:9000 \
  -e "AWS_S3_BUCKET=$AWS_S3_BUCKET" \
  -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
  -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
  planitar/test-nginx

for file in small.txt image.txt big.txt; do
  # Nginx serves static local files
  ab -n 10000 -c 1000 "http://localhost:8080/static/${file}"
  # Access s3 directly
  ab -n 10000 -c 1000 "http://${AWS_S3_BUCKET}.s3.amazonaws.com/${file}"
  # Nginx serves as proxy for s3
  ab -n 10000 -c 1000 "http://localhost:8080/s3/${file}"
  # Nginx serves as proxy for the app serving local static files
  ab -n 10000 -c 1000 "http://localhost:8080/app/${file}"
  # Nginx serves as proxy for the app serving files from s3
  ab -n 10000 -c 1000 "http://localhost:8080/app/view/${file}"
done

docker rm -f ng
```
