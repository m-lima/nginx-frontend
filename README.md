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

  1. Add to `conf/services/enabled/<server>/server.nginx` the server file
      ```nginx
      server {
        listen 80;
        server_name <server>.server.com;
        return 301 https://$server_name$request_uri;
      }

      server {
        listen 443 ssl http2;
        server_name <server>.server.com;

        ssl_certificate /var/cert/server.com/fullchain.pem;
        ssl_certificate_key /var/cert/server.com/privkey.pem;
        ssl_protocols TLSv1.2;

        charset utf-8;

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

  1. Add to `conf/services/enabled/<server>/server.nginx` the server file
      ```nginx
      # For websocket
      map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
      }

      upstream host_<server> {
        server <server>:80;
        keepalive 2;
      }

      server {
        listen 80;
        server_name <server>.server.com;

        charset utf-8;

        location ~ .* {
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_pass http://host_<server>;
        }
      }
      ```

  1. Add to `conf/services/enabled/<server>/api.<public|internal>.nginx` the api file
      ```nginx
      location [/internal]/<server> {
        rewrite .* [/internal/]<server>/ last;
      }

      location ~ ^[/internal]/<server>/(.*)$ {
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_pass http://host_<server>/$1$is_args$args;
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
