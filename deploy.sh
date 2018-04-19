#!/bin/sh
target_ns=${1:-infra}

function stage_release_diff() {
  local release=$1
  if [ -e "$release/values-stage.yml" ]; then
    RELEASE_ARGS="--values $release/values-stage.yml"
  else
    RELEASE_ARGS=""
  fi

  # this var cant be local, $? doesnt work
  diff_output=$(helm diff $RELEASE_ARGS "${release}-${target_ns}" "$release/" 2> "/tmp/${target_ns}-diff-error" )
  local diff_success=$?
  local diff_err=$(cat "/tmp/${target_ns}-diff-error")
  local diff_len=$(printf "$diff_output" | wc -l | tr -d " ")
  # TODO would be better to rely on exit codes rather than output length (helm diff doesn't have that right now)
  if ([ $diff_success -ne 0 ] || [ $diff_len -gt 1 ]); then
    printf "${diff_output}\n"
    printf "ERROR: '${diff_err}'\n"
  fi
}


all_packages=$(ls -1d */ | tr -d '/' )

# if we changed a package compared to master we must always try to deploy
# in case we changed a package then reverted it, would have to manually fix that...
# manual change made (via helm): we have no difference compared to master, but file is changed compared to master in another branch - we do nothing
# concurrent feature branches: we have no difference compared to master, and no other branch changed the file - we do nothing
# 
# One alternative would be to look for changes in other branches, and only exclude those changes (assumes good hygene wrt branch deletion)
# Otherwise parallel feature branches would override each other
#
# NB jenkins doesn't check out in a branch be default which can cause problems here 
modified_packages_in_branch=$(git diff --name-only master HEAD | cut -d'/' -f1 -s | sort | uniq)
printf "Modified packages in this branch: [ %s]\n" "$(echo $modified_packages_in_branch | tr '\n' ' ')"

# suggest: after merging to master, we apply all releases (if they are different). also periodically 

## --- For packages touched in this branch, apply helm updates if it's not a no-op --- ##

for release in ${modified_packages_in_branch}; do
  release_diff=$(stage_release_diff "$release")
  printf "release_diff: $release_diff \n"
  if [ -n "$release_diff" ]; then
    echo "Release package \"$release\" has changed, upgrading..."
    if [ -e "$release/values-stage.yml" ]; then
      RELEASE_ARGS="--values $release/values-stage.yml"
    else
      RELEASE_ARGS=""
    fi

    # won't work if release was deleted but not purged
    # prefer not to purge (are there resources we shouldn't destroy??)
    # prefer not to force or purge (probably there are resources we shouldn't destroy)
    # this will also fail if a previous revision failed and was not rolled back
    # TODO: try to rollback to previous version on failure (this can still fail if its the first release)
    helm upgrade --install --wait --timeout 120 --namespace "${target_ns}" $RELEASE_ARGS "${release}-${target_ns}" "$release/" || true 
  else
    printf "Release \"$release\" is unchanged, skipping it\n"
  fi
done

## --- Warn when helm release changed, even if we didn't touch the chart --- ##

printf "$all_packages" > /tmp/all-packages
printf "$modified_packages_in_branch" > /tmp/modified-packages
unmodified_packages=$(sort /tmp/all-packages /tmp/modified-packages | uniq -u )
printf "Unmodified packages in this branch: [ %s]\n" "$(echo $unmodified_packages | tr '\n' ' ')"

for release in ${unmodified_packages}; do
  release_diff=$(stage_release_diff "$release")
  if [ -n "$release_diff" ]; then
    printf "WARNING: Release \"$release\" deployed is different than the version in master. "
    printf "It did not change in this branch. "
    printf "If this change isn't present on another feature branch, you may want to fix this\n"
  fi
done


