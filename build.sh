docker build -t nginx .
docker stop nginx
docker rm nginx
docker network create fly
docker create \
  --publish 80:80 \
  --publish 443:443 \
  --volume /var/www/html/public:/var/www/static:ro \
  --volume browsify:/var/www/browsify:ro \
  --volume skull:/var/www/skull:ro \
  --volume sudoku:/var/www/sudoku:ro \
  --volume passer:/var/www/passer:ro \
  --volume cloud:/var/www/cloud:ro \
  --net fly \
  --name nginx \
  nginx
