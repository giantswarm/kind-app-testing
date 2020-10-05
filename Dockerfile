FROM python:3.8-slim

RUN apt update && apt install -y curl unzip jq docker.io vim tmux \
  && curl -L https://kind.sigs.k8s.io/dl/v0.7.0/kind-Linux-amd64 \
    -o /usr/local/bin/kind && chmod +x /usr/local/bin/kind \
  && curl -L https://storage.googleapis.com/kubernetes-release/release/v1.18.9/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl \
  && curl -L https://get.helm.sh/helm-v2.16.12-linux-amd64.tar.gz \
    | tar -zx --strip-components=1 --directory=/usr/local/bin linux-amd64/helm \
  && curl -L https://github.com/giantswarm/gsctl/releases/download/0.24.3/gsctl-0.24.3-linux-amd64.tar.gz \
    | tar -zx --strip-components=1 --directory=/usr/local/bin gsctl-0.24.3-linux-amd64/gsctl

RUN curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.0.53.zip -o awscliv2.zip \
  && unzip awscliv2.zip \
  && ./aws/install \
  && rm -r awscliv2.zip ./aws

COPY ./kube-app-testing.sh /usr/local/bin

CMD ["kube-app-testing.sh", "-h"]
