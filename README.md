
# Helm CD Pipeline With Jenkins

This repo sets up a pipeline in Jenkins to deploy the helm charts stored in the `charts` folder. Changes made to individual charts will be deployed to a `test` namespace. Changes that make it to master will then be deployed to a `stage` namespace.  

A sample chart, for Prometheus, is included for illustrative purposes.

## Getting Started

To deploy locally from scratch, run `setup-local.sh` on your local machine. This starts Minikube and deploys a Jenkins chart into it. The Jenkins chart included contains the job definition pointing to this repo. If you already have a Jenkins set up, you only need to set up a multibranch pipeline to point to (a fork of) this repo. Note that the job must be configured to check out a branch, not in detached HEAD mode, for the deploy script to run successfully. 

## How it works

On each feature branch, any changes relative to master will be deployed. On master, all changes made since the last successful build will be applied. 

To avoid making duplicate revisions in the helm release history, `helm update` is only applied when the new release would be different than the currently deployed revision. This is calculated using the `helm diff` plugin. Note that this means any changes made to the releases outside of helm, eg directly with kubectl, will not be rectified automatically (helm isn't a config management tool!). 

## Workflow

This pipeline assumes a simple development model that uses short-lived feature branches, merged via PRs to the master branch.

1. In **local development**, the user can run the deploy script to their own namespace to get quick feedback on their changes
2. When a **feature branch**     is created, the changes are pushed to a test environment to check the changes checked-in are as intended
3. After **merging to master**, the changes from the new commits on master will be deployed into the staging environment 

We assume there won't be many feature branches open at the same time *that modify the same chart*, so contention in deploying to a test environment will not be a big problem. 

## Layout

The folders under `charts` are all eligible for deployment by the deploy script. The script will expect the folder name to be set to the release name, and will expect the helm chart itself to be in a subdirectory `chart`.

If `values-test.yml` or `values-s101.yml` are present in the folder for an individual chart, then any values specified there will override the defaults specified in the `Values.yaml` file in the individual chart, when deploying into the corresponding namespace. Full details of values / value overrides in helm are documented [here](https://github.com/kubernetes/helm/blob/master/docs/chart_template_guide/values_files.md).

## Developing locally

The deploy script has been written so it can be executed locally as well as in the CD system. To do so just run `./deploy.sh <target_k8s_namespace>`. An optional second parameter may be specified which specifies a git revision, by default this is 'master'. Changes since the specified revision will be deployed. 

Note that, since we calculate changes with `git diff`, new charts must be added to the index before they will be deployed. OTOH the chart that is deployed will be the version from the working directory. To avoid conflicts, it is suggested to use a unique namespace name, and one that easily identifies it as a development space - e.g. `dev-myfeature`.

Since helm's tiller is essentially a privileged user in Kubernetes, and Helm does not handle AuthN/AuthZ, a user may deploy to any namespace they have access to. 

## Manual Tasks

### Deploying a single item
### Promoting to Prod
### Doing a full deploy

TODO

## Access Control

TODO
