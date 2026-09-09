#!/bin/sh
# Builds a YJIT-enabled Ruby from source into /opt/rbenv/versions/3.3.11-yjit, since this
# environment's containers are ephemeral and cache.ruby-lang.org is blocked by egress policy
# (github.com is reachable, so we build from a shallow clone of ruby/ruby instead). Idempotent:
# skips the build entirely if that Ruby is already present and YJIT-capable. Never blocks
# session start -- always exits 0, warning on stderr if the build can't complete.
set -eu

PREFIX=/opt/rbenv/versions/3.3.11-yjit
TAG=v3_3_11

# Nothing to build where the ruby on PATH already has YJIT: any dev machine, as opposed to
# the bare containers this script exists for.
if ruby --yjit -e 'exit(RubyVM::YJIT.enabled? ? 0 : 1)' >/dev/null 2>&1; then
  exit 0
fi

if "$PREFIX/bin/ruby" --yjit -e 'exit(RubyVM::YJIT.enabled? ? 0 : 1)' >/dev/null 2>&1; then
  exit 0
fi

echo "build_yjit_ruby: building YJIT-enabled Ruby ($TAG) into $PREFIX..." >&2

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

if ! git clone --depth 1 --branch "$TAG" https://github.com/ruby/ruby.git "$WORKDIR/ruby" >&2; then
  echo "build_yjit_ruby: clone failed, skipping (YJIT build will be retried next session)" >&2
  exit 0
fi

cd "$WORKDIR/ruby"
if ! ./autogen.sh >&2 \
  || ! ./configure --enable-yjit --prefix="$PREFIX" >&2 \
  || ! make -j"$(nproc)" >&2 \
  || ! make install >&2; then
  echo "build_yjit_ruby: build failed, skipping (YJIT build will be retried next session)" >&2
  exit 0
fi

echo "build_yjit_ruby: done -- use $PREFIX/bin/ruby --yjit (RubyVM::YJIT.enable needs the --yjit flag present at boot)" >&2
