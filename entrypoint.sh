#! /usr/bin/env bash
set -e

watch="false"
multithreaded="false"
while [[ $# -gt 0 ]]
do
  arg="$1"
  case $arg in
    -m|--multithreaded)
    multithreaded="true"
    shift
    ;;
    -w|--watch)
    watch="true"
    shift
    ;;
  esac
done

if [[ "$multithreaded" == "true" ]]; then
  args="-Dpreview_mt"
else
  args=""
fi

echo "### \`crystal spec ${args}\`"

if [[ "$watch" == "true" ]]; then
  CRYSTAL_WORKERS=$(nproc) watchexec -e cr -c -r -w src -w spec -- crystal spec --error-trace -v ${args}
else
  CRYSTAL_WORKERS=$(nproc) crystal spec --error-trace -v ${args}
fi
