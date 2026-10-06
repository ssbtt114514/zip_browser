#!/usr/bin/env bash
# 用法：tool/pack_plugin.sh <插件目录> [输出.zip]
set -e
python3 "$(dirname "$0")/pack_plugin.py" "$@"
