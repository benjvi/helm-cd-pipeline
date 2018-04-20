# assume helm is already set up with the latest  kube-diff installed
minikube start --cpus 4 --memory 8192
kubectl create ns test
kubectl create ns stage
helm init --wait
helm install --name jenkins --namespace jenkins --values jenkins/values-override.yml jenkins/
