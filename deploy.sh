#!/bin/sh
all_packages=$(ls -1d */ | tr -d '/' )

# if we changed a package compared to master we must always try to deploy
# in case we changed a package then reverted it, would have to manually fix that...
# manual change made (via helm): we have no difference compared to master, but file is changed compared to master in another branch - we do nothing
# concurrent feature branches: we have no difference compared to master, and no other branch changed the file - we do nothing
# 
# One alternative would be to look for changes in other branches, and only exclude those changes (assumes good hygene wrt branch deletion)
# Otherwise parallel feature branches would override each other
#TODO: run git if its available so this works properly locally
modified_packages_in_branch=$1

printf "Modified packages: [ %s]\n" "$(echo $modified_packages_in_branch | tr '\n' ' ')"

# TODO: warn on unchanged releases that have a diff

# suggest: after merging to master, we apply all releases (if they are different). also periodically 

function stage_release_diff() {
  local release=$1
  if [ -e "$release/values-stage.yml" ]; then
    RELEASE_ARGS="--values $release/values-stage.yml"
  else
    RELEASE_ARGS=""
  fi

  local diff_output=$(helm diff $RELEASE_ARGS "$release" "$release/" 2> /tmp/stage-diff-error )
  local diff_err=$(</tmp/stage-diff-error)
  local diff_success=$?
  local diff_len=$(printf "$diff_output" | wc -l | tr -d " ")
  # TODO would be better to rely on exit codes rather than output length (helm diff doesn't have that right now)
  if ([ $diff_success -ne 0 ] || [ $diff_len -gt 1 ]); then
    printf "${diff_output}\n"
    printf "ERROR: '${diff_err}'\n"
  fi
}

for release in ${modified_packages_in_branch}; do
  release_diff=$(stage_release_diff "$release")
  if [ -n "$release_diff" ]; then
    echo "Release package \"$release\" has changed, upgrading..."
    # won't work if release was deleted but not purged
    # prefer not to purge (are there resources we shouldn't destroy??)
    # prefer not to force or purge (probably there are resources we shouldn't destroy)
    # this will also fail if a previous revision failed and was not rolled back
    # TODO: try to rollback to previous version on failure (this can still fail if its the first release)
    helm upgrade --install --wait --timeout 120 --namespace "infra" $RELEASE_ARGS "$release" "$release/" || true 
  else
    printf "Release \"$release\" is unchanged, skipping it\n"
  fi
done

printf "$all_packages" > /tmp/all-packages
printf "$modified_packages_in_branch" > /tmp/modified-packages

unmodified_packages=$(sort /tmp/all-packages /tmp/modified-packages | uniq -u )
printf "Unmodified packages: [ %s]\n" "$(echo $unmodified_packages | tr '\n' ' ')"

for release in ${unmodified_packages}; do
  release_diff=$(stage_release_diff "$release")
  if [ -n "$release_diff" ]; then
    echo "WARNING: Release \"$release\" has been updated outside of this branch. You may want to fix this"    
  fi
done

