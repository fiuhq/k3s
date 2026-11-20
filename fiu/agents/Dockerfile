# The fleet's Paseo agent image: the fiuhq/paseo fork's daemon (docker/base/Dockerfile, built from fork main) plus
# GitHub's CLI, so an agent in a pod can clone, push and open its pull request. The agent CLIs are not in the image:
# the Sandbox installs them into the pod's home with each vendor's own installer, so their updaters keep them current.
#   docker buildx build --build-arg BASE=fiuhq/paseo:fork-<sha> -t fiuhq/paseo-agent:<sha> fiu/agents
ARG BASE
FROM ${BASE}
USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl gnupg openssh-client; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*
# Left as root: the base entrypoint prepares mounted volumes as root, then runs the daemon and its agents as paseo.
