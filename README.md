To run:

```shell
# Edit deploy.sh: instance type and ami, then run the tests
AWS_S3_BUCKET="iguide.plntr" ./aws/deploy.sh
```

Or do it manually:
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

# Benchmark Results

## Mean latency

We run 1000 GET requests in a row (by `ab -c 1 -n 1000 .../small.txt`)
for a 13-byte `small.txt` file.

```shell
$ cat small.txt
Hello World!
```
Note: no special kernel tuning for better network performance was done.

|  Results            | `t1.micro` Latency, ms | `t2.small` Latency, ms |
|--------------|------------:|------------:|
| Apache       | 1.160       | 1.160       |
| Nginx        | 1.476       | 0.516       |
| App          | 1.361       | 0.488       |
| S3           | 133.188     | 130.023     |
| Nginx+App    | 2.931       | 1.043       |
| Nginx+S3     | 151.525     | 133.306     |
| App+S3       | 247.013     | 241.796     |
| Nginx+App+S3 | 264.335     | 244.868     |

`t1.micro` instance is 1 vCPU with 0.615GiB RAM, low network performance.
`t2.small` instance is 2 2.5GHz vCPUs with with 2GiB RAM, low network performance.

**XXX** we have to run the same tests on instances with high expected network
performance, e.g. `m3.xlarge`.
