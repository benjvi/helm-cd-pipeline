#!/bin/sh
target_ns=${1?"Mandatory first arg missing: target namespace"}
diff_base_ref=${2:-master}

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

cd charts
all_charts=$(ls -1d */ | tr -d '/' )
cd -
# if we changed a package compared to master we must always try to deploy
# in case we changed a package then reverted it, would have to manually fix that...
# manual change made (via helm): we have no difference compared to master, but file is changed compared to master in another branch - we do nothing
# concurrent feature branches: we have no difference compared to master, and no other branch changed the file - we do nothing
# 
# One alternative would be to look for changes in other branches, and only exclude those changes (assumes good hygene wrt branch deletion)
# Otherwise parallel feature branches would override each other
#
# NB jenkins doesn't check out in a branch be default which can cause problems here 
# Also note we calculate diffs using the current working state not with HEAD - so its the same as what we use to deploy
modified_charts_git=$(git diff --name-only "${diff_base_ref}" charts/ | cut -d'/' -f2 -s | sort | uniq)
printf "Modified charts vs git ref ${diff_base_ref}: [ %s]\n" "$(echo $modified_charts_git | tr '\n' ' ')"

# suggest: after merging to master, we apply all releases (if they are different). also periodically 
## --- For charts touched in this branch, apply helm updates if it's not a no-op --- ##

current_hash=$(git rev-parse --verify --short HEAD)

for chart_name in ${modified_charts_git}; do
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
    helm upgrade --install --wait --timeout 120 --namespace "${target_ns}" $RELEASE_ARGS "${release}" "charts/$chart_name/chart/" --set "git-hash=$current_hash" || true 
  else
    printf "Deployed release \"$release\" is already up to date, skipping it\n"
  fi
done

## --- Warn when helm release changed, even if we didn't touch the chart --- ##

printf "$all_charts" > /tmp/all-charts
printf "$modified_charts_git" > /tmp/modified-charts
unmodified_charts_git=$(sort /tmp/all-charts /tmp/modified-charts | uniq -u )
printf "Unmodified charts vs git ref ${diff_base_ref}: [ %s]\n" "$(echo $unmodified_charts_git | tr '\n' ' ')"

for chart_name in ${unmodified_charts_git}; do
  release_diff=$(get_release_diff "$chart_name")
  release="${chart_name}-${target_ns}"
  if [ -n "$release_diff" ]; then
    printf "Release diff: \n${release_diff}\n"
    printf "WARNING: Release \"$release\" deployed is different than the version in master. "
    printf "It did not change in this branch. "
    printf "If this change isn't present on another feature branch, you may want to fix this\n"
  fi
done


