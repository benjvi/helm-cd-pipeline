FROM lachlanevenson/k8s-helm:v2.8.2

ENV HELM_HOME=/etc/helm
RUN apk add --no-cache git bash curl && mkdir -p $HELM_HOME/plugins
RUN helm plugin install https://github.com/databus23/helm-diff
