
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

Since helm's tiller is normally a privileged user in Kubernetes, and Helm does not handle authorization, a user may deploy to any namespace they have access to. 

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

A safer approach would be to forbid modifications with kubectl altogether to production and production-like environments (only retaining break-glass roles). Standard user credentials could be issued with read-only access, while the Service Account for Tiller can retain its permissions to deploy anywhere in the cluster. 

### Multiple clusters

In realistic use-cases we may have some environments which are in physically separate  clusters. Since we keep our release information in git, and our helm commands are already namespaced, all we need to do is modify our deployment scripts to pass the appropriate tiller host to the helm commands. It *should* make it possible to use the same client certs for authorization where appropriate, however its probably better to have separate credentials. This means that the user/service-user is separately, explicitly authorized to use each cluster.  

### Secrets

This repo does not show how to deal with config values that cannot be checked in. There are some options for injecting secrets:

1. Supply them at deploy time with the `-set` flag on upgrade. However, helm currently stores its releases in plaintext, and will return this info to any authorized user. As helm [adds better functionality for dealing with secrets](https://github.com/kubernetes/helm/issues/2196) this could become the preferred option
2. Initialize the secrets with a default value and then modify the value afterwards outside of helm. As helm allows for manual changes this should be persisted. The problem comes when someone later changes the value in helm, which will require you to make the modification again. 
3. Create them out-of-band and refer to them in your kubernetes manifests. This works better in a small number of namespaces and where the number of secrets we have is small. The more secrets we move out of helm, the more we lose the benefits of helm packaging. Nevertheless, this is the only real option for very secure secrets. 

### Publishing Charts

There are two benefits of publishing charts:
 - Control access to released versions separately from access to source
 - Easier to work with in helm, e.g. helm commands show chart versions  

While the second point is a nice improvement to UX, it is the first one that will determine whether publishing charts is necessary. This could support a separate workflow for modifying config, or making charts available more widely.

Chart servers can be private and can be as simple as [publishing to a Github repository](https://hackernoon.com/using-a-private-github-repo-as-helm-chart-repo-https-access-95629b2af27c). Despite the relative simplicity of this model neither this or introducing a separate pipeline for chart-related changes are likely to be worthwhile unless there are specific requirements around access control. 

### GitOps

It would be a *relatively* simple extension to enable triggering deployments via git / PRs for gated deployments to prod(/like) environments. For those environments, separate repo(s) would be created which would contain the description for each environment. That description would likely contain:
 - a list of charts that should be deployed the environment
 - the version for each chart, expressed as a git ref of this repo
 - optionally, some variable overrides (this would allow for deployment of old packages into new environments)

To support this, the deploy script would need to be changed to checkout this charts repo in a specific revision and parse the environment descriptions. 

## Comparisons

### Jenkins X

Jenkins X is a wrapper around Jenkins that integrates with Kubernetes, adds Continuous Deployment capabilities, and has a more opinionated approach to the deployment pipeline. It manages different 'environments' as namespaces within kubernetes, and out of the box it understands how to deploy helm charts as part of the promotion process.

It creates preview environments from feature branches, and allows for either manual or automatic promotions to environments like stage and prod. Environments are each managed in their own repo via GitOps. This repo should contain dependencies for each 'app' to be deployed into the repo, and it also allows for environment-specific manifests to be added. It seems like Jenkins X expects each app to be in its own repo, which might be overkill for infrastructure services.

In general, it seems like the general approach is interesting, perhaps moreso for microservices than the kind of services we want to deploy here. It also seems like it [is planned to work with multi-cluster promotions too](https://github.com/jenkins-x/jx/issues/479), at which point it may be worth re-evaluating its use.

### Weave Flux

Weave Flux's normal mode of operation deals with continuously applying updated images from a registry to any form of controller (i.e. a deployment/daemonset/etc) that consumes those images. Since we want to bind the deployment configuration together with container versions and with supporting resources like config maps, this model doesn't match too well for deploying infrastructure services. However, Flux does also support [integrating with helm releases](https://github.com/weaveworks/flux/blob/master/site/helm/helm-integration.md).

In this mode, charts live in a single repo, similarly to in this repository. Flux also requires you to have some CRDs which define how the charts will be deployed into releases in specific namespaces. These CRDs allow you to pass in values overrides, for values which need to be different between environments. However, it does not currently support deploying different *versions* of charts in different environments.

Based on these CRDs, helm continuously syncs the chart/release definitions in the repository with the deployed versions in tiller. Remember that tiller cannot guarantee the state of resources matches the release in all circumastances. So, if access to the cluster is allowed in helm only, *and* if you are operating in a continuous deployment environment where chart versions should be the same across all environments, this model could work well. It is early days for the helm integration, having just started in February 2018. 

## Others

There are [many other](https://www.infoq.com/news/2018/03/skaffold-kubernetes) frameworks [to compare](https://blog.hasura.io/draft-vs-gitkube-vs-helm-vs-ksonnet-vs-metaparticle-vs-skaffold-f5aa9561f948), a lot of which seem to be relatively new, and come with significant backing. Given the amount of activity in this space, these are worth keeping an eye on.
