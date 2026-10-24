#!/bin/zsh
# Local half of the spike. Mirrors the CI container step. usage: local_run.sh RUN_ID MODE [PLATFORM]
# MODE = container|native. Workdir layout: $W/fixture, $W/out/$RUN_ID, $W/deps-$RUN_ID
set -eu
W=${W:?}; RUN_ID=$1; MODE=$2; PLAT=${3:-linux/amd64}
SPEC=$W/repo/stage OUT=$W/out/$RUN_ID DEPS=$W/deps-$RUN_ID
IMAGE_INDEX=docker.io/library/python@sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70
rm -rf $OUT $DEPS; mkdir -p $OUT $DEPS; chmod 777 $OUT $DEPS
now() { python3 -c 'import time;print(time.time())'; }
if [[ $MODE == container ]]; then
  docker pull -q --platform $PLAT $IMAGE_INDEX >/dev/null
  docker image inspect $IMAGE_INDEX --format '{{json .}}' > $OUT/image-inspect.json
  COMMON=(--rm --platform $PLAT --user 65534:65534 --cap-drop ALL --security-opt no-new-privileges
    --read-only --tmpfs /tmp:rw,size=256m --memory 2g --cpus 2 --pids-limit 512
    -v $SPEC:/spec:ro -v $DEPS:/deps)
  t0=$(now)
  docker run $COMMON $IMAGE_INDEX sh /spec/run_stage.sh install python /src /deps /out /spec
  t1=$(now)
  docker run $COMMON --network none -v $W/fixture:/src:ro -v $OUT:/out $IMAGE_INDEX sh /spec/run_stage.sh test python /src /deps /out /spec
  t2=$(now)
  docker run --rm --platform $PLAT $IMAGE_INDEX sh -c 'python -VV; python -m pip --version; uname -a' > $OUT/container-identity.txt
else
  PY=$HOME/.local/share/uv/python/cpython-3.12.11-macos-aarch64-none/bin/python3.12
  t0=$(now)
  sh $SPEC/run_stage.sh install $PY $W/fixture $DEPS $OUT $SPEC
  t1=$(now)
  sh $SPEC/run_stage.sh test $PY $W/fixture $DEPS $OUT $SPEC
  t2=$(now)
  { $PY -VV; $PY -m pip --version; uname -a; } > $OUT/native-identity.txt
fi
python3 -c "import json,sys;a,b,c=map(float,sys.argv[1:]);print(json.dumps({'install_s':round(b-a,3),'test_s':round(c-b,3)}))" $t0 $t1 $t2 > $OUT/wall.json
python3 -c "import json,platform,os;print(json.dumps({'host':'local-mac','uname':' '.join(platform.uname()),'docker':os.popen('docker version --format {{.Server.Version}}').read().strip(),'nproc':os.cpu_count()},indent=2))" > $OUT/runner-identity.json
rm -rf $DEPS
cat $OUT/digests.json $OUT/wall.json
