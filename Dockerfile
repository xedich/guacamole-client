#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

#
# Dockerfile for guacamole-client
#

# Use args for Tomcat image label to allow image builder to choose alternatives
# such as `--build-arg TOMCAT_JRE=jre8-alpine`
#
ARG TOMCAT_VERSION=8.5
ARG TOMCAT_JRE=jdk8

# Use official maven image for the build
FROM maven:3-jdk-8 AS builder

# Use args to build radius auth extension such as
# `--build-arg BUILD_PROFILE=lgpl-extensions`
ARG BUILD_PROFILE

# Build environment variables
ENV \
    BUILD_DIR=/tmp/guacamole-docker-BUILD

# Add configuration scripts
COPY guacamole-docker/bin/ /opt/guacamole/bin/

# Copy source to container for sake of build
COPY . "$BUILD_DIR"

RUN rm -rf 
RUN rm -rf "$BUILD_DIR/guacamole-server" "$BUILD_DIR/.gitmodules" "$BUILD_DIR/guacamole-docker/bin/entrypoint.sh"
# Run the build itself
RUN /opt/guacamole/bin/build-guacamole.sh "$BUILD_DIR" /opt/guacamole "$BUILD_PROFILE"





# Use Debian as base for the build
FROM tomcat:${TOMCAT_VERSION}-${TOMCAT_JRE} AS guacd-builder

ARG DEBIAN_RELEASE=buster-backports
RUN grep " ${DEBIAN_RELEASE} " /etc/apt/sources.list || echo >> /etc/apt/sources.list \
    "deb http://deb.debian.org/debian ${DEBIAN_RELEASE} main contrib non-free"

ARG PREFIX_DIR=/usr/local/guacamole
ARG SERVER_SOURCE=guacamole-server

# Build arguments
ARG BUILD_DIR=/tmp/guacd-docker-BUILD
ARG BUILD_DEPENDENCIES="              \
        autoconf                      \
        automake                      \
        freerdp2-dev                  \
        gcc                           \
        libcairo2-dev                 \
        libgcrypt-dev                 \
        libjpeg62-turbo-dev           \
        libossp-uuid-dev              \
        libpango1.0-dev               \
        libpulse-dev                  \
        libssh2-1-dev                 \
        libssl-dev                    \
        libtelnet-dev                 \
        libtool                       \
        libvncserver-dev              \
        libwebsockets-dev             \
        libwebp-dev                   \
        make"

# Do not require interaction during build
ARG DEBIAN_FRONTEND=noninteractive

# Bring build environment up to date and install build dependencies
RUN apt-get update                                              && \
    apt-get install -t ${DEBIAN_RELEASE} -y $BUILD_DEPENDENCIES && \
    rm -rf /var/lib/apt/lists/*

# Add configuration scripts
COPY "${SERVER_SOURCE}/src/guacd-docker/bin" "${PREFIX_DIR}/bin/"

# Copy source to container for sake of build
COPY "$SERVER_SOURCE" "$BUILD_DIR"

# Build guacamole-server from local source
RUN "${PREFIX_DIR}/bin/build-guacd.sh" "$BUILD_DIR" "$PREFIX_DIR"

# Record the packages of all runtime library dependencies
RUN ${PREFIX_DIR}/bin/list-dependencies.sh     \
        ${PREFIX_DIR}/sbin/guacd               \
        ${PREFIX_DIR}/lib/libguac-client-*.so  \
        ${PREFIX_DIR}/lib/freerdp2/*guac*.so   \
        > ${PREFIX_DIR}/DEPENDENCIES











# For the runtime image, we start with the official Tomcat distribution
FROM tomcat:${TOMCAT_VERSION}-${TOMCAT_JRE}
ARG DEBIAN_RELEASE=buster-backports
RUN grep " ${DEBIAN_RELEASE} " /etc/apt/sources.list || echo >> /etc/apt/sources.list \
    "deb http://deb.debian.org/debian ${DEBIAN_RELEASE} main contrib non-free"


ARG PREFIX_DIR=/usr/local/guacamole

# Runtime environment
ENV LC_ALL=C.UTF-8
ENV LD_LIBRARY_PATH=${PREFIX_DIR}/lib
ENV GUACD_LOG_LEVEL=info

ARG RUNTIME_DEPENDENCIES="            \
        netcat-openbsd                \
        ca-certificates               \
        ghostscript                   \
        fonts-liberation              \
        fonts-dejavu                  \
        xfonts-terminus"

# Do not require interaction during build
ARG DEBIAN_FRONTEND=noninteractive

# This is where the build artifacts go in the runtime image
WORKDIR /opt/guacamole

# Copy artifacts from builder image into this image
COPY --from=builder /opt/guacamole/ .
COPY --from=guacd-builder ${PREFIX_DIR} ${PREFIX_DIR}

# Bring runtime environment up to date and install runtime dependencies
RUN apt-get update                                                                                       && \
    apt-get install -t ${DEBIAN_RELEASE} -y --no-install-recommends $RUNTIME_DEPENDENCIES                && \
    apt-get install -t ${DEBIAN_RELEASE} -y --no-install-recommends $(cat "${PREFIX_DIR}"/DEPENDENCIES)  && \
    apt-get install -t ${DEBIAN_RELEASE} -y --no-install-recommends sudo                                 && \
    rm -rf /var/lib/apt/lists/*

# Link FreeRDP plugins into proper path
RUN ${PREFIX_DIR}/bin/link-freerdp-plugins.sh \
        ${PREFIX_DIR}/lib/freerdp2/libguac*.so

# Checks the operating status every 5 minutes with a timeout of 5 seconds
HEALTHCHECK --interval=5m --timeout=5s CMD nc -z 127.0.0.1 4822 || exit 1

# Create a new user guacd
ARG UID=1000
ARG GID=1000
RUN groupadd --gid $GID guacd
RUN useradd --system --create-home --shell /usr/sbin/nologin --uid $UID --gid $GID guacd
#----------------------------------------------------------------------------------------------

# Create a new user guacamole
ARG UID=1001
ARG GID=1001
RUN groupadd --gid $GID guacamole
RUN useradd --system --create-home --shell /usr/sbin/nologin --uid $UID --gid $GID guacamole


ENTRYPOINT ["/opt/guacamole/bin/entrypoint.sh" ]

