# assume helm is already set up with the latest (HEAD) of kube-diff installed
minikube start
kubectl create ns infra
helm init --wait
helm install --name jenkins \
      --namespace jenkins \
            stable/jenkins
