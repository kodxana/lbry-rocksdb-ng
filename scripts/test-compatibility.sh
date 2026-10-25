#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
output_dir=${TEST_OUTPUT_DIR:-ci-results}
baseline=${1:-}
if [ "$#" -gt 1 ] || { [ -n "$baseline" ] && [ ! -f "$baseline" ]; }; then
    echo 'Usage: sh scripts/test-compatibility.sh [released-cp313-wheel]' >&2
    exit 2
fi
for version in 3.9 3.13; do
    set -- "$output_dir/python$version/"*.whl
    if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
        echo "Expected one wheel in $output_dir/python$version; run scripts/test.sh $version first." >&2
        exit 1
    fi
done

image_dir=$(mktemp -d)
mkdir "$image_dir/baseline"
if [ -n "$baseline" ]; then
    cp "$baseline" "$image_dir/baseline/"
fi
volume=
container=
cleanup() {
    if [ -n "$container" ]; then
        docker rm -f "$container" >/dev/null
    fi
    if [ -n "$volume" ]; then
        docker volume rm "$volume" >/dev/null
    fi
    rm -f "$image_dir/39" "$image_dir/313" "$image_dir/baseline/"*
    rmdir "$image_dir/baseline"
    rmdir "$image_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Use the same interpreter images as the wheel builds, without rebuilding RocksDB.
for version in 39 313; do
    docker build --target "python$version" --iidfile "$image_dir/$version" \
        -f docker/Dockerfile.test .
done
volume=$(docker volume create)

run_step() {
    version=$1
    action=$2
    database=$3
    compression=$4
    case "$version" in
        3.9) image=$(cat "$image_dir/39") ;;
        3.13) image=$(cat "$image_dir/313") ;;
        baseline) image=$(cat "$image_dir/313") ;;
    esac
    container=$(docker create --network none --cpus 2 --memory 2g \
        --mount "type=volume,source=$volume,target=/data" "$image" \
        timeout --kill-after=30 120 sh -ec '
            python -m pip install --disable-pip-version-check --no-index --no-deps /tmp/wheels/*.whl
            python /tmp/persistence.py "$@"
        ' sh "$action" "/data/$database" --compression "$compression")
    if [ "$version" = baseline ]; then
        docker cp "$image_dir/baseline" "$container:/tmp/wheels"
    else
        docker cp "$output_dir/python$version" "$container:/tmp/wheels"
    fi
    docker cp tests/persistence.py "$container:/tmp/persistence.py"
    status=0
    docker start -a "$container" || status=$?
    if [ "$status" -eq 0 ]; then
        status=$(docker inspect --format '{{.State.ExitCode}}' "$container")
    fi
    docker rm "$container" >/dev/null
    container=
    return "$status"
}

for compression in snappy zlib lz4 lz4hc zstd; do
    run_step 3.9 create "from39-$compression" "$compression"
    run_step 3.13 update "from39-$compression" "$compression"
    run_step 3.9 verify-updated "from39-$compression" "$compression"
    run_step 3.13 create "from313-$compression" "$compression"
    run_step 3.9 update "from313-$compression" "$compression"
    run_step 3.13 verify-updated "from313-$compression" "$compression"
    if [ -n "$baseline" ]; then
        run_step baseline create "upgrade-$compression" "$compression"
        run_step 3.13 update "upgrade-$compression" "$compression"
        run_step baseline verify-updated "upgrade-$compression" "$compression"
        run_step 3.13 create "downgrade-$compression" "$compression"
        run_step baseline update "downgrade-$compression" "$compression"
        run_step 3.13 verify-updated "downgrade-$compression" "$compression"
    fi
done
