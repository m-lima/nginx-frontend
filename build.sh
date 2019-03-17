docker build -t nginx .
docker rm nginx
docker create \
  --publish 80:80 \
  --publish 443:443 \
  --volume /var/www/html/public:/var/www/static \
  --volume browsify:/var/www/browsify \
  --volume skull:/var/www/skull \
  --link browsify \
  --link sync \
  --link soccer-pong \
  --link skull \
  --name nginx \
  nginx
