# External changes

Add a CNAME record to the DNS poiting to '@'

# Statically served
## Map the volume

* **Docker volume**

  1. Use the *volume-updater*
      ```bash
      docker build -t volume-updater .
      docker run \
        --volume <volume_name>:/data \
        --rm \
        volume-updater \
      bash -c 'cp -r /your/stuff/root/* /data/.'
      ```

  1. Update `build.sh` to add the volume
      ```bash
      --volume <volume_name>:/var/www/<location_name>
      ```

* **Direct reference**

  1. Update `build.sh` to add a volume mapped from the host machine
      ```bash
      --volume /host/path/to/content:/var/www/<location_name>
      ```

## Add **nginx** entry

  1. Add to `conf/conf.d/include/server` the server configuration
      ```nginx
      server {
        listen 80;
        server_name <server>.server.com;
        return 301 https://$server_name$request_uri;
      }

      server {
        listen 443 ssl;
        server_name <server>.server.com;

        ssl_certificate /var/cert/server.com/fullchain.pem;
        ssl_certificate_key /var/cert/server.com/privkey.pem;

        charset utf-8;
        access_log /var/log/nginx/<server>.access.log main;

        resolver 127.0.0.1;

        location / {
          expires 30d;

          root  /var/www/<server>;
          index index.html;

          try_files $uri /index.html;
        }
      }
      ```

# Proxied server

## Add **nginx** entry

  1. Add to `conf/conf.d/include/server` the server configuration
      ```nginx
      # For websocket
      map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
      }

      server {
        listen 80;
        server_name <server_name>.server.com;

        charset utf-8;
        access_log /var/log/nginx/<server_name>.access.log main;

        resolver 127.0.0.1;

        location ~ .* {
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_pass http://<server_name>;
        }
      }
      ```

  1. Add to `conf/conf.d/include/api/<public|internal>` the server configuration
      ```nginx
      # public
      location /<location_name>/ {
        resolver 127.0.0.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://<container_name>/;
      }

      # internal
      location /internal/<oauthed_location_name>/ {
        resolver 127.0.0.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://<container_name>/;
      }
      ```

  1. Add a *systemd* entry
      ```systemd
      [Unit]
      Description=SuperName
      After=docker.service dependency_name.service
      Requires=docker.service dependency_name.service
      StopWhenUnneeded=yes

      [Service]
      Restart=always
      ExecStart=/usr/bin/docker start -a super-name
      ExecStop=/usr/bin/docker stop super-name
      ```

  1. Add the dependency to *nginx.service*
      ```systemd
      [Unit]
      Description=Web Gateway for server.com
      After=docker.service dependency_one.service dependency_two.service super_service.service
      Requires=docker.service dependency_one.service dependency_two.service super_service.service
      ```

  1. Link the container on *build.sh*
      ```bash
      docker create \
        --publish 80:80 \
        --publish 443:443 \
        --link super-service \
        --name nginx \
        nginx
      ```
