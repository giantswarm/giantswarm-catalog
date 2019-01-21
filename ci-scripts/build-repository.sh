#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly REPONAME=$1
readonly PERSONAL_ACCESS_TOKEN=$2

readonly APPS_FILE=./APPS
readonly HELM_URL=https://storage.googleapis.com/kubernetes-helm
readonly HELM_TARBALL=helm-v2.11.0-linux-amd64.tar.gz
readonly HELM_REPO_URL=https://giantswarm.github.com/${REPONAME}

main() {
    setup_helm_client

    if ! download_latest_charts; then
        log_error "Not all charts could be downloaded!"
    fi

    if ! sync_repo "${HELM_REPO_URL}"; then
        log_error "Not all charts could be packaged and synced!"
    fi

    cleanup
}

cleanup() {
  rm -rf sync linux-amd64 ${HELM_TARBALL}
}

setup_helm_client() {
    echo "Setting up Helm client..."

    curl --user-agent curl-ci-sync -sSL -o "${HELM_TARBALL}" "${HELM_URL}/${HELM_TARBALL}"
    tar xzfv "${HELM_TARBALL}"

    PATH="$(pwd)/linux-amd64/:$PATH"

    helm init --client-only
    helm repo add "${REPONAME}" "${HELM_REPO_URL}"
}

download_latest_charts() {
  while IFS="" read -r app || [ -n "${app}" ]
  do
      release_url=$(curl -s "https://api.github.com/repos/${app}/releases/latest" | jq -r .assets[0].browser_download_url)
      chart=$(echo "${release_url}" | tr "/" " " | awk '{print $NF}')

      # Check if release exists and not already present
      if [ "${release_url}" == "null" ];then
        echo "No GitHub release of '${app}' found!"
        exit 1
      elif [ -e "${chart}" ];then
        echo "${chart} already present, skipping!"
      else
        echo "Downloading chart '${chart}'..."
        wget -q -P sync "${release_url}"
      fi
  done < ${APPS_FILE}
}

sync_repo() {
    local repo_url="${1?Specify repo url}"

    if [ ! -d "sync" ]; then
      echo "No new releases found. Terminating"
      return 0
    fi

    echo "Syncing repo..."
    if helm repo index --url "${repo_url}" --merge "index.yaml" "sync"; then
        mv -f ./sync/* .

        git add ./*.tgz
        git add index.yaml

        git -c user.name="Taylor Bot" -c user.email="dev@giantswarm.io" commit -m "Auto build: ${REPONAME}"
        git push -q "https://${PERSONAL_ACCESS_TOKEN}@github.com/giantswarm/${REPONAME}.git" master
    else
        log_error "Exiting because unable to update index. Not safe to push update."
        exit 1
    fi
    return 0
}

log_error() {
    printf '\e[31mERROR: %s\n\e[39m' "$1" >&2
}

main
