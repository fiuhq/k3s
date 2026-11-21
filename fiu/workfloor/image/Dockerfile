# syntax=docker/dockerfile:1.12
#
# The personal Workfloor's web image, built from the fiuhq/workfloor-ui fork's source (image/build.sh sends it here as
# a git archive). flxbl's own image installs Font Awesome Pro through flxbl's package cache, which only flxbl's runners
# and VPN reach; this one installs it from Font Awesome's registry with the operator's own token, given as a build
# secret so it never enters a layer. The lockfile pins the Pro tarballs to the cache, so the copy inside the build points
# them at npm.fontawesome.com first (the source's own lockfile is never changed).
#
# One image, two uses: `node server.js` (the web server, which migrates the database as it starts) and
# `node postgres.mjs migrate` (the same migrations on their own).
ARG NODE_IMAGE=node:24.18.0-bookworm-slim

FROM ${NODE_IMAGE} AS build
WORKDIR /app
ENV OPENUI_TELEMETRY_DISABLED=1 NEXT_TELEMETRY_DISABLED=1
COPY package.json package-lock.json ./
RUN sed -i 's#https://npm-proxy.flxbl.io/#https://npm.fontawesome.com/#g' package-lock.json \
 && printf '%s\n' '@fortawesome:registry=https://npm.fontawesome.com/' \
      '//npm.fontawesome.com/:_authToken=${FONTAWESOME_PACKAGE_TOKEN}' > .npmrc
RUN --mount=type=secret,id=fontawesome,required=true --mount=type=cache,target=/root/.npm \
    FONTAWESOME_PACKAGE_TOKEN="$(cat /run/secrets/fontawesome)" npm ci --no-audit --no-fund \
 && rm .npmrc
COPY . .
# The source's own .npmrc names flxbl's cache; nothing installs after this, so it goes.
RUN rm -f .npmrc && NODE_OPTIONS=--max-old-space-size=6144 npm run build \
 && cp -R .next/static .next/standalone/.next/static

FROM ${NODE_IMAGE} AS runtime
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 HOSTNAME=0.0.0.0 PORT=3100 WORKFLOOR_DATA_DIR=/app/data
COPY --from=build --chown=node:node /app/.next/standalone ./
RUN mkdir -p /app/data && chown node:node /app/data
USER node
EXPOSE 3100
CMD ["node", "server.js"]
