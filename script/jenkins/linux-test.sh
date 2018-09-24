#!/usr/bin/env bash
set -euox pipefail

source ./_beats/dev-tools/common.bash

jenkins_setup

cleanup() {
  rm -rf $TEMP_PYTHON_ENV
  make stop-environment fix-permissions
}
trap cleanup EXIT

make
make testsuite

export GOPACKAGES=$(go list github.com/elastic/apm-server/...| grep -v /vendor/ | grep -v /scripts/cmd/)

go get github.com/jstemmer/go-junit-report

go get github.com/axw/gocov/gocov
go get gopkg.in/matm/v1/gocov-html

go get github.com/axw/gocov/...
go get github.com/AlekSi/gocov-xml

export COV_FILE="build/test-report.cov"
export OUT_FILE="build/test-report.out"
go test -race ${GOPACKAGES} -v -coverprofile=${COV_FILE} -bench 2>&1 ${OUT_FILE}
cat ${OUT_FILE} | go-junit-report > build/junit-report.xml
gocov convert ${COV_FILE} | gocov-html > build/coverage-report.html
gocov convert ${COV_FILE} | gocov-xml > build/coverage-report.xml

make coverage-report
