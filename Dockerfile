FROM node:24-trixie-slim@sha256:8c8f12cedb96c3b59642cf30d713943c2b223990c9919b96a141681f62e6e292 AS packages

# Set environment variables
ENV PYTHON=/usr/bin/python3 \
    NODE_ENV=production \
    NODE_OPTIONS="--no-node-snapshot"


# From here on we use the least-privileged `node` user to run the backend.
USER node

WORKDIR /app

# Copy files needed by Yarn
COPY --chown=node:node .yarn ./.yarn
COPY --chown=node:node .yarnrc.yml  ./
COPY --chown=node:node backstage.json ./

# Copy repo skeleton first, to avoid unnecessary docker cache invalidation.
# The skeleton contains the package.json of each package in the monorepo,
# and along with yarn.lock and the root package.json, that's enough to run yarn install.

COPY --chown=node:node yarn.lock package.json ./
RUN tar xzf /tmp/app/skeleton.tar.gz && rm -rf /tmp/skeleton.tar.gz

RUN corepack enable && \
    yarn workspaces focus --all --production && \
    yarn cache clean && \
    find node_modules -type d \( -name test -o -name tests -o -name __tests__ \) -exec rm -rf {} + && \
    find node_modules -type f \( -name "*.spec.js" -o -name "*.test.js" -o -name "*.spec.ts" -o -name "*.test.ts" \) -delete && \
    find node_modules -type f -name "docker-compose.yml" -delete && \
    find node_modules -type f -name "Dockerfile" -delete

# Copy any other files that we need at runtime
COPY --chown=node:node app-config*.yaml ./
COPY --chown=node:node backstage.json ./
COPY --chown=node:node packages/backend/src/instrumentation.js ./

# This will include the examples, if you don't need these simply remove this line
COPY --chown=node:node examples ./examples


RUN printf "[credential \"https://code.siemens.com\"]\n username = __token__\n" >> ~/.gitconfig \
    && git config --global credential.helper store \
    && git config --global user.name '__token__' \
    && printf "#!/bin/sh\nexec echo \"\$GITLAB_CSC_TOKEN\"\n" >> /app/git-askpass-helper.sh \
    && chmod +x /app/git-askpass-helper.sh

ENV GIT_ASKPASS=/app/git-askpass-helper.sh

CMD ["node","--inspect", "--require", "./instrumentation.js", "packages/backend", "--config", "app-config.production.yaml"]
