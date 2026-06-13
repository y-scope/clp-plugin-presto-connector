# syntax=docker/dockerfile:1
#
# Layers the matching-arch CLP plugin .rpm onto an upstream Presto base image
# and (optionally) symlinks the installed files into the base image's plugin
# discovery path.
#
# Build args:
#   BASE_IMAGE             — upstream Presto image to layer onto
#   PLUGIN_SYMLINK_SOURCE  — absolute path of the installed plugin directory
#   PLUGIN_SYMLINK_TARGET  — absolute path for the symlink in the base image's
#                            plugin discovery tree (empty → no symlink created)
#
# Build context: a directory containing the *.rpm file(s) to install.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Re-declare after FROM so the values are available inside the build stage.
# (Pre-FROM ARGs go out of scope after the FROM line per Docker's ARG scoping rules.)
ARG PLUGIN_SYMLINK_SOURCE
ARG PLUGIN_SYMLINK_TARGET

COPY . /tmp/clp-plugin-rpm/
RUN rpm -i /tmp/clp-plugin-rpm/*.rpm \
 && rm -rf /tmp/clp-plugin-rpm \
 && if [ -n "${PLUGIN_SYMLINK_TARGET}" ]; then \
        mkdir -p "$(dirname "${PLUGIN_SYMLINK_TARGET}")"; \
        ln -sfn "${PLUGIN_SYMLINK_SOURCE}" "${PLUGIN_SYMLINK_TARGET}"; \
    fi
