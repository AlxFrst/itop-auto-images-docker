# 🚀 iTop Docker Images

Automated Docker images builder for iTop ITSM.

[![Build and Push](https://github.com/AlxFrst/itop-auto-images-docker/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/AlxFrst/itop-auto-images-docker/actions/workflows/build-and-push.yml)

## 📋 Available Versions

The following versions are automatically built and available in the GitHub Container Registry:

| Version | PHP Version |
|---------|-------------|
| itop-3.0.1 | 7.4 |
| itop-3.0.2 | 7.4 |

## 🔧 How to use

You can use these images with docker run or with docker-compose.

### 🐳 Using docker-compose

Create a `docker-compose.yml` file with the following content:

```yaml
services:
  itop:
    image: ghcr.io/alxfrst/itop-auto-images-docker/itop-3.0.1 # Change this to the version you want
    ports:
      - "80:80"
    volumes:
      - ./itop_extensions:/var/www/html/itop/extensions
      - ./itop_data:/var/www/html/itop/data
      - ./itop_conf:/var/www/html/itop/conf
      - ./itop_logs:/var/www/html/itop/log
      - ./itop_env:/var/www/html/itop/env-production
    command: /bin/bash -c "chown -R www-data:www-data /var/www/html/itop && /usr/sbin/apache2ctl -D FOREGROUND"
  mysql:
    image: mysql:5.7
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: itop
      MYSQL_USER: itop
      MYSQL_PASSWORD: itop
    volumes:
      - ./mysql_data:/var/lib/mysql
```

Then run:

```bash
docker-compose up -d
```

### 📦 Using docker run

```bash
docker run -d -p 80:80 \
  -v ./itop_extensions:/var/www/html/itop/extensions \
  -v ./itop_data:/var/www/html/itop/data \
  -v ./itop_conf:/var/www/html/itop/conf \
  -v ./itop_logs:/var/www/html/itop/log \
  -v ./itop_env:/var/www/html/itop/env-production \
  ghcr.io/alxfrst/itop-auto-images-docker/itop-3.0.1
```

## 🛠️ Initial Setup

1. Access iTop setup at http://localhost/setup
2. Follow the installation wizard
3. Configure the database connection:
   - Database server: mysql
   - Login: itop
   - Password: itop
   - Database name: itop

## 👥 Contributing

To add a new version:

1. Update the `inventory.yml` file with the new version details
2. Create a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.