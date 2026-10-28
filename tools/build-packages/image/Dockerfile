# syntax=docker/dockerfile:1

# Init-container installer image for the CLP Presto connector.
#
# Bundles both plugins and, when run, copies each into a mounted target directory. The
# build context is an extracted package install tree (coordinator/ + worker/), assembled by
# build-installer-init-image.sh. See tools/build-packages/README.md.

# The installer only runs busybox's own sh/cp/mkdir to copy files; it never executes the
# plugin, so the libc flavor is irrelevant. Pin the small musl variant for a tiny image.
FROM busybox:1.37.0-musl

# Match the .deb/.rpm install root (PLUGIN_ROOT) so all channels share one layout.
COPY coordinator /opt/clp-plugin-presto-connector/coordinator
COPY worker /opt/clp-plugin-presto-connector/worker
COPY --chmod=0755 entrypoint.sh /usr/local/bin/install-clp-plugin

ENTRYPOINT ["/usr/local/bin/install-clp-plugin"]
