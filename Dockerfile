# conversionmedia/ci-build:php8.4
# Build and deploy tools for the GitLab CI pipelines (Composer, wp-cli, rsync/SSH, git-ftp).
#
# Build & push (works from an Apple Silicon Mac as well):
#   docker buildx build --platform linux/amd64 \
#     -t conversionmedia/ci-build:php8.4 \
#     -t conversionmedia/ci-build:php8.4-2026.11 \
#     --push .

ARG PHP_VERSION=8.4
# Composer stays on major 2 (a future Composer 3 should not slip in unnoticed).
# All other tools take the newest version at build time, as in the 7.4 image.
# Any of them can be pinned without touching this file, e.g.:
#   --build-arg WP_ROCKET_CLI_VERSION=v1.3 --build-arg WP_CLI_VERSION=2.12.0
ARG COMPOSER_VERSION=2

FROM composer:${COMPOSER_VERSION} AS composer

FROM --platform=linux/amd64 php:${PHP_VERSION}-cli-bookworm

ARG WP_CLI_VERSION=latest
ARG WP_ROCKET_CLI_VERSION=trunk
ARG CACHETOOL_VERSION=latest

ENV COMPOSER_ALLOW_SUPERUSER=1 \
	COMPOSER_NO_INTERACTION=1 \
	WP_CLI_ALLOW_ROOT=1

# System tools. Debian's curl ships with SFTP support (libssh2), so the
# self-compiled libssh2/curl from the 7.4 image is no longer needed.
# zip and mysqli are baked in, so Composer platform checks pass (wpstarter needs ext-mysqli).
# Existing before_script steps that install zip still work.
RUN apt-get update -qq \
	&& apt-get install -qqy --no-install-recommends \
		git \
		git-ftp \
		lftp \
		rsync \
		openssh-client \
		unzip \
		libzip-dev \
	&& docker-php-ext-install -j"$(nproc)" zip mysqli \
	&& rm -rf /var/lib/apt/lists/* \
	&& curl -V | grep -qw sftp

# Composer (major version from the official image)
COPY --from=composer /usr/bin/composer /usr/bin/composer

# wp-cli with the WP Rocket package
RUN if [ "$WP_CLI_VERSION" = "latest" ]; then \
		url="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"; \
	else \
		url="https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar"; \
	fi \
	&& curl -fsSL -o /usr/local/bin/wp "$url" \
	&& chmod +x /usr/local/bin/wp \
	&& wp package install "wp-media/wp-rocket-cli:${WP_ROCKET_CLI_VERSION}" --allow-root

# cachetool (OPcache/APCu control, part of the published 7.4 image but missing in its Dockerfile)
RUN if [ "$CACHETOOL_VERSION" = "latest" ]; then \
		url="https://github.com/gordalina/cachetool/releases/latest/download/cachetool.phar"; \
	else \
		url="https://github.com/gordalina/cachetool/releases/download/${CACHETOOL_VERSION}/cachetool.phar"; \
	fi \
	&& curl -fsSL -o /usr/local/bin/cachetool "$url" \
	&& chmod +x /usr/local/bin/cachetool

# Print the versions that actually ended up in the image (visible in the build log)
RUN mkdir -p ~/.ssh/ \
	&& php -v \
	&& php -m | grep -qx zip \
	&& php -m | grep -qx mysqli \
	&& composer --version \
	&& wp --version --allow-root \
	&& wp package list --allow-root \
	&& curl -V | head -1 \
	&& git-ftp --version \
	&& cachetool --version
