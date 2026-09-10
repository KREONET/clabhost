# Offline extension drop-in

Put `.vsix` files here and the extension step installs every one of them before
it tries the marketplace -- `install.sh` runs it, and so does
`code-server/seed-extensions.sh` on its own. A host with no egress needs nothing
else.

An offline install resolves **no dependencies** -- it reports success and
silently skips them -- so drop the dependencies in too. See
[`docs/airgap.ko.md`](../../docs/airgap.ko.md) for how to collect them.

The files are gitignored. This directory travels with `/opt/clabhost`.
