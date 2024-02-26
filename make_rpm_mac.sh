#!/bin/bash

BLUE='\033[1;94m'
RED='\033[0;31m'
NC='\033[0m'

log_error() {
    echo -e "${RED}[ERROR] ${NC}$1"
}

log_info() {
    echo -e "${BLUE}[INFO] ${NC}$1"
}

if [ $# -eq 0 ]; then
    log_error "Usage: $0 VERSION for regular rpms"
    exit 1
fi

if [ ! -f "./packaging/rpm/"*.spec ]; then
    log_error "Missing ./packaging/rpm/*.spec"
    exit 1
fi

VERSION=$1

log_info "Running QEMU (colima) service..."
colima start > /dev/null 2>&1

if [ "$(docker ps -a --format '{{.Names}}' | grep -w builder)" == "builder" ]; then
    if [ "$(docker inspect -f '{{.State.Running}}' builder 2>/dev/null)" == "false" ]; then
        log_info "Starting docker container for builder"
        docker start builder > /dev/null 2>&1
        docker exec builder bash -c "yum clean all" > /dev/null 2>&1
        docker exec builder bash -c "rm -rf /build" > /dev/null 2>&1
    fi
else
    log_info "Building docker container for builds (first time)"
    docker run --privileged -d --name builder --network host rockylinux:9 /bin/sleep infinity > /dev/null 2>&1
    log_info "Preparing container for redborder builds..."
    docker exec builder bash -c "yum install -y epel-release && yum install -y make git mock" > /dev/null 2>&1
    docker exec builder bash -c "git config --global --add safe.directory /build" > /dev/null 2>&1
fi

docker cp ./ builder:/build > /dev/null 2>&1

log_info "Creating sdk9 link to mock"
docker exec builder bash -c "echo \"config_opts['use_host_resolv'] = True\" >> /etc/mock/default.cfg" > /dev/null 2>&1

log_info "Building RPM for webui"
docker exec builder bash -c "cd /build/ && make rpm"

mkdir -p ./packaging/rpm/pkgs > /dev/null 2>&1
rm -rf ./packaging/rpm/pkgs/*.rpm > /dev/null 2>&1
log_info "Sending rpms to host machine..."
docker cp builder:/build/packaging/rpm/pkgs/. ./packaging/rpm/pkgs > /dev/null 2>&1

log_info "Stopping container"
docker stop builder > /dev/null 2>&1

log_info "Stopping colima service"
colima stop > /dev/null 2>&1
