#!/bin/sh
# TODO : filter by directories which had changes on current branch
# Alternatively, look for changes in other branches, and only exclude those changes (assumes good hygene wrt branch deletion)
# Otherwise parallel feature branches would override each other
for i in $(ls -1d */); do
  release=$(echo "$i" | tr -d '/')
  if [ -e "$release/values-stage.yml" ]; then
    RELEASE_ARGS="--values $release/values-stage.yml"
  else
    RELEASE_ARGS=""
  fi

  release_needed=false
  diff_output=$(helm diff $RELEASE_ARGS "$release" "$i")
  diff_success=$?
  diff_len=$(printf "$diff_output" | wc -l | tr -d " ")
  if ([ $diff_success -ne 0 ] || [ $diff_len -gt 1 ]); then
    printf "$diff_output \n"
    release_needed=true
  fi

  if [ "$release_needed" = true ]; then
    echo "Release \"$release\" has changed, upgrading..."
    # won't work if release was deleted but not purged
    # prefer not to purge (are there resources we shouldn't destroy??)
    helm upgrade --install --wait --timeout 120 --namespace "infra" $RELEASE_ARGS "$release" "$i" || true 
  else
    printf "Release \"$release\" is unchanged, skipping it\n"
  fi
done
