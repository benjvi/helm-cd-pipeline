def label = "worker-${UUID.randomUUID().toString()}"

podTemplate(label: label, containers: [
  containerTemplate(name: 'helm-diff', image: 'benjvi/k8s-helm-diff:latest', command: 'cat', ttyEnabled: true)
]) {
  node(label) {
    def myRepo = checkout scm
    def gitCommit = myRepo.GIT_COMMIT
    def gitBranch = myRepo.GIT_BRANCH
    def shortGitCommit = "${gitCommit[0..10]}"
    def previousGitCommit = sh(script: "git rev-parse ${gitCommit}~", returnStdout: true)
    
    container('helm-diff') {
      sh """
      # TODO this should be in docker image, for the jenkins user
      mkdir -p /home/jenkins/.helm/plugins/helm-diff
      cp /etc/plugins/helm-diff/* /home/jenkins/.helm/plugins/helm-diff/

      helm home
      helm version
      helm plugin list"""
  
      sh "./deploy.sh" 
    }
  }
}

