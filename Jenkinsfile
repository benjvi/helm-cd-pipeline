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

    if ( gitBranch == "master" ) {
      container('helm-diff') { 
        // manually configured jenkins job to check out branch not detached build 
        // TODO: master script needs to parse revisions differently
        sh "./deploy.sh s101"
      }
    } else {
      // here need to checkout master to compare
      sh "git branch master origin/master || true" 
      container('helm-diff') { 
        sh "./deploy.sh infra"
      }    
    }
  }
}

