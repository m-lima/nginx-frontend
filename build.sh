docker build -t nginx-fly .
docker stop nginx-fly
docker rm nginx-fly
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
  --name nginx-fly \
  nginx-fly
