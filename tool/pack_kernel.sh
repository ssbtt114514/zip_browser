#!/usr/bin/env bash
# 用法：tool/pack_kernel.sh <内核目录> [输出.zbk]
#       tool/pack_kernel.sh --demo [输出.zbk]
set -e
python3 "$(dirname "$0")/pack_kernel.py" "$@"
