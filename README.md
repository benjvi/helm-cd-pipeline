
# Helm CD Pipeline With Jenkins

This repo sets up a pipeline in Jenkins to deploy the helm charts stored in the `charts` folder. Changes made to individual charts will be deployed to a `test` namespace. Changes that make it to master will then be deployed to a `stage` namespace.  

A sample chart, for Prometheus, is included for illustrative purposes.

## Getting Started

To deploy locally from scratch, run `setup-local.sh` on your local machine. This starts Minikube and deploys a Jenkins chart into it. The Jenkins chart included contains the job definition pointing to this repo. 

If you already have a Jenkins set up, you only need to set up a multibranch pipeline to point to (a fork of) this repo. Note that the job must be configured to check out a branch, not in detached HEAD mode, for the deploy script to run successfully. 

## How it works

On each feature branch, any changes relative to master will be deployed. On master, all changes made since the last successful build will be applied. 

To avoid making duplicate revisions in the helm release history, `helm update` is only applied when the new release would be different than the currently deployed revision. This is calculated using the `helm diff` plugin. This does mean any changes made to the releases outside of helm, eg directly with kubectl, will not be rectified automatically (helm [isn't a config management tool](https://github.com/kubernetes-helm/community/blob/master/helm-v3/009-package_manager.md)!). 

## Workflow

This pipeline assumes a simple development model that uses short-lived feature branches, merged via PRs to the master branch.

1. In **local development**, the user can run the deploy script to their own namespace to get quick feedback on their changes
2. When a **feature branch** is created (or updated), the changes are pushed to a test environment to check the changes checked-in are as intended
3. After **merging to master**, the changes from the new commits on master will be deployed into the staging environment 

We assume there won't be many feature branches open at the same time *that modify the same chart*, so contention in test environment use will not be a big problem. 

## Layout

The folders under `charts` are all eligible for deployment by the deploy script. The script will expect the folder name to be set to the release name, and will expect the helm chart itself to be in a subdirectory `chart`.

If `values-test.yml` or `values-stage.yml` are present in the folder for an individual chart, then any values specified there will override the defaults specified in the `Values.yaml` file in the individual chart, when deploying into the corresponding namespace. You may also add override values for additional environments in the same format: `values-<env>.yml`. Full details of values / value overrides in helm are documented [here](https://github.com/kubernetes/helm/blob/master/docs/chart_template_guide/values_files.md).

## Developing locally

The deploy script has been written so it can be executed locally as well as in the CD system. To do so just run `./deploy.sh <target_k8s_namespace>`. An optional second parameter may be specified which specifies a git revision, by default this is 'master'. Changes since the specified revision will be deployed. 

Note that, since we calculate changes with `git diff`, new charts must be added to the index before they will be deployed. OTOH the chart that is deployed will be the version from the working directory. To avoid conflicts, it is suggested to use a unique namespace name, and one that easily identifies it as a development space - e.g. `dev-myfeature`.

Since helm's tiller is essentially a privileged user in Kubernetes, and Helm does not handle AuthN/AuthZ, a user may deploy to any namespace they have access to. 

## Other Manual Tasks

### Deploying a single item

If you have multiple changed charts in your local workspace or branch, there may be occasions when you want to deploy the updates to just one of them. When you do this you still want to make sure that you don't create duplicate revisions and you use the appropriate values override files. There is a separate script provided for this: `deploy-one.sh`.

You can call this script by `./deploy-one.sh <target_k8s_namespace> <chart_name>`. This will deploy the release regardless of the git changeset, however, as with `deploy.sh` it will not deploy if the chart is identical to the current revision in the helm release.

### Promoting to Prod

We are not pushing versioned artefacts as part of the pipeline, so for reproducible releases we rely on the versioning in this repo. 

1. Check out the git version to deploy with. Aprat from exceptional cases, this will be HEAD on master
2. Check release is the same version we deployed in stage:
 - helm diff shows no difference to version in stage (this will include changes to chart version or app version)
 - Git commit added to release matches e.g. `helm release get prometheus-stage | grep git-hash` 
3. Then check the changes are as expected vs prod with helm diff. 
4. Deploy using `deploy-one.sh`, for example: `./deploy-one.sh prod prometheus`

If something still goes wrong during the rollout, you can rollback to the previous version with helm, e.g. `helm rollback prometheus-prod 0`

## Access Control

See [here](https://github.com/kubernetes/helm/blob/master/docs/securing_installation.md#best-practices-for-securing-helm-and-tiller). In a nutshell, Tiller in a secure installation should have a TLS cert issued by your PKI. In this [secure setup](https://github.com/kubernetes/helm/blob/master/docs/tiller_ssl.md) the helm CLI must use a client side cert, which ensures only authorized access. Lack of authentication within tiller means that separate tillers are needed where separate administrative roles are required.

## Build Environment / Docker Image

Jenkins is configured to run its jobs in a Docker image. This image is identical to `lachlanevanson/k8s-helm`, except that it adds helm-diff. The checked-in Dockerfile can be used to reproduce this Docker image.

## Extensions

### Reverting Manual Changes

The helm model of doing deployments [is intended to allow for some manual changes](https://github.com/kubernetes/helm/issues/2070). So applying an upgrade to a release, with [any kind of flags](https://github.com/kubernetes/helm/issues/3798), will not guarantee overriding changes made manually. The only way to ensure the full configuration in the cluster matches that in the release is to delete and recreate the release (i.e. to nuke it from orbit). This is undesirable for a number of reasons.

With that in mind, it is preferable to identify and rectify manual changes by another means. You can extract the manifests for the current release by `helm get manifests <release>`, then you can use a tool like [kubediff](https://github.com/weaveworks/kubediff) to compare those manifests with the current state of the cluster. Taken further, one of the goals of [Weave Flux](https://github.com/weaveworks/flux) seems to be to continuously apply such changes. 

### Multiple clusters

In realistic use-cases we may have some environments which are in physically separate  clusters. Since we keep our release information in git, and our helm commands are already namespaced, all we need to do is modify our deployment scripts to pass the appropriate tiller host to the helm commands. It *should* make it possible to use the same client certs for authorization (where appropriate). 

### Secrets

This repo does not show how to deal with config values that cannot be checked in. There are some options for injecting secrets:

1. Supply them at deploy time with the `-set` flag on upgrade. However, helm currently stores its releases in plaintext, and will return this info to any authorized user. As helm [adds better functionality for dealing with secrets](https://github.com/kubernetes/helm/issues/2196) this could become the preferred option
2. Initialize the secrets with a default value and then modify the value afterwards outside of helm. As helm allows for manual changes this should be persisted. The problem comes when someone later changes the value in helm, which will require you to make the modification again. 
3. Create them out-of-band and refer to them in your kubernetes manifests. This works better in a small number of namespaces and where the number of secrets we have is small. The more secrets we move out of helm, the more we lose the benefits of helm packaging 

### Publishing Charts

TODO

## Comparisons

### Jenkins X

Jenkins X is a wrapper around Jenkins that integrates with Kubernetes, adding Continous Deployment, and has a more opinionated approach to the deployment pipeline.

### Weave Flux

### Terraform
