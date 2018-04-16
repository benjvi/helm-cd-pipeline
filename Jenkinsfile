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
    def modifiedPackagesInBranch = sh(script: "git diff --name-only master HEAD | cut -d'/' -f1 -s | sort | uniq", returnStdout: true)

    container('helm-diff') {
      sh """
      helm home
      helm version
      helm plugin list"""
  
      sh """
      modified=\$(printf "jenkins\ncockroachdb\n")
      ./deploy.sh ${env.modified}"""
    }
  }
}

