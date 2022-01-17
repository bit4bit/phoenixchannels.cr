#!/bin/sh

set -ex

mix local.hex --force
mix local.rebar --force
mix deps.get
mix phx.server
