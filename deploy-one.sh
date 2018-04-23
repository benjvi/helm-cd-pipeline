#!/bin/bash
target_ns=${1?"Mandatory first arg missing: target namespace"}
chart_name=${2?"Mandatory second arg missing: chart name"}

function get_release_diff() {
  local chart_name=$1
  local release="${chart_name}-${target_ns}"
  if [ -e "charts/${chart_name}/values-${target_ns}.yml" ]; then
    RELEASE_ARGS="--values charts/${chart_name}/values-${target_ns}.yml"
  else
    RELEASE_ARGS=""
  fi

  # this var cant be local, $? doesnt work
  diff_output=$(helm diff $RELEASE_ARGS "${release}" "charts/${chart_name}/chart/" 2> "/tmp/${target_ns}-diff-error" )
  local diff_success=$?
  local diff_err=$(cat "/tmp/${target_ns}-diff-error")
  local diff_len=$(printf "$diff_output" | wc -l | tr -d " ")
  # TODO would be better to rely on exit codes rather than output length (helm diff doesn't have that right now)
  if ([ $diff_success -ne 0 ] || [ $diff_len -gt 1 ]); then
    printf "${diff_output}\n"
    printf "ERROR: '${diff_err}'\n"
  fi
}

release_diff=$(get_release_diff "$chart_name")
release="${chart_name}-${target_ns}"
if [ -n "$release_diff" ]; then
  printf "Release diff: \n${release_diff}\n"
  echo "Package for release \"$release\" is different than the currently deployed version, upgrading..."
  if [ -e "charts/$chart_name/values-${target_ns}.yml" ]; then
    RELEASE_ARGS="--values charts/$chart_name/values-${target_ns}.yml"
  else
    RELEASE_ARGS=""
  fi

  # won't work if release was deleted but not purged
  # prefer not to purge (are there resources we shouldn't destroy??)
  # prefer not to force or purge (probably there are resources we shouldn't destroy)
  # this will also fail if a previous revision failed and was not rolled back
  # TODO: try to rollback to previous version on failure (this can still fail if its the first release)
  helm upgrade --install --wait --timeout 120 --namespace "${target_ns}" $RELEASE_ARGS "${release}" "charts/$chart_name/chart/" || true 
else
  printf "Deployed release \"$release\" is already up to date, skipping it\n"
fi
