ARG ELIXIR_VERSION=1.4.5

FROM elixir:${ELIXIR_VERSION} as builder

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update -q && apt-get install -y build-essential libtool autoconf curl

RUN DEBIAN_CODENAME=$(sed -n 's/VERSION=.*(\(.*\)).*/\1/p' /etc/os-release) && \
    curl -q https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
    echo "deb http://deb.nodesource.com/node_8.x $DEBIAN_CODENAME main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update -q && \
    apt-get install -y nodejs

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix hex.info


WORKDIR /src
ADD ./ /src/

# Set default environment for building
ENV ALLOW_PRIVATE_REPOS=true
ENV MIX_ENV=prod

RUN mix deps.get
RUN cd /src/apps/bors_frontend && npm install && npm run deploy
RUN mix phx.digest
RUN mix release --env=$MIX_ENV

####

FROM debian:jessie-slim
RUN apt-get update -q && apt-get install -y git-core libssl1.0.0 curl ca-certificates

ENV DOCKERIZE_VERSION=v0.6.0
RUN curl -Ls https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz | \
    tar xzv -C /usr/local/bin

ADD ./docker-entrypoint /usr/local/bin/bors-ng-entrypoint
COPY --from=builder /src/_build/prod/rel/ /app/

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PORT=4000
ENV DATABASE_AUTO_MIGRATE=true
ENV ALLOW_PRIVATE_REPOS=true

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/bors-ng-entrypoint"]
CMD ["./bors_frontend/bin/bors_frontend", "foreground"]

EXPOSE 4000
