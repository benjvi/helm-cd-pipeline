def label = "worker-${UUID.randomUUID().toString()}"

podTemplate(label: label, containers: [
  containerTemplate(name: 'helm-diff', image: 'benjvi/k8s-helm-diff:v2.8.2-5', command: 'cat', ttyEnabled: true)
]) {
  node(label) {
    def myRepo = checkout scm
    def gitCommit = myRepo.GIT_COMMIT
    def gitBranch = myRepo.GIT_BRANCH
    def shortGitCommit = "${gitCommit[0..10]}"
    def previousGitCommit = sh(script: "git rev-parse ${gitCommit}~", returnStdout: true)
    // manually configured jenkins job to check out branch not detached build 
    // deploy script requires this
    def lastAppliedHash = getLastSuccessfulCommit()

    if ( gitBranch == "master" ) {
      // this is a git hash representing the null state
      // if we dont find a previous successful build then we apply everything
      // this may not be appropriate if (e.g.) importing a pre-existing repo
      echo(lastAppliedHash)
      container('helm-diff') { 
        sh "./deploy.sh s101 \"${lastAppliedHash}\""
      }
    } else {
      // need to checkout master in order to compare as part of deploy
      sh "git branch master origin/master || true" 
      container('helm-diff') { 
        sh "./deploy.sh infra"
      }    
    }
  }
}

def getLastSuccessfulCommit() {
  def lastSuccessfulHash = sh(script: "git hash-object -t tree /dev/null | tr -d \"[:space:]\"", returnStdout: true)
  def lastSuccessfulBuild = currentBuild.rawBuild.getPreviousSuccessfulBuild()
  if ( lastSuccessfulBuild ) {
    lastSuccessfulHash = commitHashForBuild( lastSuccessfulBuild )
  }
  return lastSuccessfulHash
}

/**
 * Gets the commit hash from a Jenkins build object, if any
 */
@NonCPS
def commitHashForBuild( build ) {
  def scmAction = build?.actions.find { action -> action instanceof jenkins.scm.api.SCMRevisionAction }
  return scmAction?.revision?.hash
}
