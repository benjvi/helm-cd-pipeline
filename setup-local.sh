# assume helm is already set up with the latest (HEAD) of kube-diff installed
minikube start
kubectl create ns infra
helm init --wait
# TODO pipeline plugin needs upgrading for multibranch plugin to work
# also will need to create test jobs manually (and git creds)
helm install --name jenkins \
      --namespace jenkins \
            jenkins/
