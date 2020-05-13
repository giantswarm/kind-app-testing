# kube-app-testing

This script builds and tests a helm chart using either a KinD cluster, or a full Giant Swarm tenant
cluster. The only required parameter is `[chart name]`, which needs to be a name of the chart which
 is present in directory `helm/`.

## Installation

Checkout the repo and make `kube-app-testing.sh` executable and visible in your `$PATH`.

## Usage

Type:

```bash
kind-app-testing.sh -h
```

## How it works

A single test cycle works as below:

1. If there's an old test cluster, it is deleted.
1. Chart is validated and source files are templated using [`architect`](https://github.com/giantswarm/architect)
1. Linting is run using [chart-testing](https://github.com/helm/chart-testing).
1. Chart is built using `helm`
1. The following loop is run for every test config file present in `helm/[app]/ci/*yaml`. If there
   are no config files, the loop is started just once, without any config.
    1. New kubernetes cluster is created. Currently, only `kind` is supported, so a new `kind` cluster
       is started using an embedded kind config file. You can override
       the config file using command line option `-i`. When the cluster is up, `app-operator`,
       `chart-operator` and `chart-museum` are deployed.
    1. If there's a file `helm/[chart name]/si/pre-test-hook.sh`, it is executed. The
       `KUBECONFIG` variable is set to point to the test cluster for the script execution.
    1. Chart is pushed to the `chart-musuem` repository in the cluster.
    1. The App CR is created to deploy the application.
    1. If the directory `test/kat` exists at the top level of repository, python tests are
       started by executing the command:

       ```bash
       pipenv run pytest \
       --kube-config /kube.config \
       --chart-name ${chart_name} \
       --values-file ../../${config_file} \
       --junitxml=../../${test_res_file}
       ```

       As you can see, test results are saved in the directory `test-results/` in junit format
       for each of the test runs.

    1. If `-k` was given as command line option, the program exits keeping the test cluster.

## Requirements

Following tools must be installed in the system:

- kind
- helm
- curl
- jq

## Development setup for functional tests with python

When you develop your tests intended to run with `pytest`, you can shorten you test-feedback
loop considerably by not running the full tool every single time, but just executing
`pytest` the same way the tool does.

In order to do that and start working on a new project, that has a helm chart, but no
python tests, follow this steps:

1. Make sure you have `python 3.7` installed and selected as default python interpreter,
   then run

   ```bash
   pip install pipenv
   ```

2. Go to your application repo, create the directory `test/kat` and `cd` to it

   ```bash
   mkdir test/kat
   cd test/kat
   ```

3. Run  to create a `pipenv` managed project.

   ```bash
   pipenv --python 3.7
   ```

4. Install `pytest` and basic recommended libs in the `pipenv` virtual environment:

   ```bash
   pipenv install pytest pytest-rerunfailures kubetest kubernetes
   ```

   Commit `Pipfile` and `Pipfile.lock` files.

5. Write your tests. To get started faster, you might want to include this
   [`conftest.py`](https://github.com/giantswarm/giantswarm-todo-app/blob/master/test/kat/conftest.py)
   file to get fixtures offering you the tested chart name and the path and values loaded
   from `helm/[app]/ci*.yaml` file used for this test run.

6. Use the tool to create a `kind` cluster you can use for your testing. Ask to not delete it
   by passing `-k` option:

   ```bash
   kind-app-testing.sh -c [app] -k
   ```

7. Now you're good to directly execute your tests against the test cluster:

   ```bash
   pipenv run pytest \
      --kube-config /tmp/kind_test/kubei.config \
      --chart-name [app] \
      --values-file [""|../../[app]/ci/[config_file.yaml]
   ```

## Integration with CircleCI

Integration with CircleCI requires a job definition similar to the one below. Note that the last step in the job
is important to ensure any dangling resources are removed if a run fails midway through.

```yaml
jobs:
  run_kat_tests:
    machine:
      image: ubuntu-1604:201903-01
    working_directory:
      ~/giantswarm-todo
    steps:
      - restore_cache:
          key: repo-{{ .Environment.CIRCLE_SHA1 }}-<< pipeline.git.tag >>
      - run: pyenv versions
      - run: pyenv global 3.7.0
      - run: python --version
      - run: pip install pipenv aws-shell
      - run: curl -Lo /tmp/kind "https://github.com/kubernetes-sigs/kind/releases/download/v0.7.0/kind-$(uname)-amd64"
      - run: chmod +x /tmp/kind
      - run: curl -Lo /tmp/helm.tar.gz https://get.helm.sh/helm-v2.16.5-linux-amd64.tar.gz
      - run: tar zxf /tmp/helm.tar.gz -C /tmp && mv /tmp/linux-amd64/helm /tmp/helm
      - run: /tmp/helm init -c
      - run: curl -Lo /tmp/kind-app-testing.sh -q https://raw.githubusercontent.com/giantswarm/kube-app-testing/master/kube-app-testing.sh
      - run: chmod +x /tmp/kind-app-testing.sh
      - run: curl -Lo /tmp/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.18.0/bin/linux/amd64/kubectl
      - run: chmod +x /tmp/kubectl
      - run:
          command: PATH="/tmp:$PATH" kind-app-testing.sh -c giantswarm-todo-app -t giantswarm --cluster-name wealdy-test -a ${GS_API_KEY} -r ${GS_RELEASE} --availability-zone ${GS_AVAILABILITY_ZONE} --giantswarm-api-url ${GS_API_URL}
          environment:
            AWS_ACCESS_KEY_ID: ${CI_AWS_ACCESS_KEY_ID}
            AWS_SECRET_ACCESS_KEY: ${CI_AWS_SECRET_ACCESS_KEY}
      - store_test_results:
          path: test-results
      - store_artifacts:
          path: test-results
      - run:
          name: Cleanup resources
          command: PATH="/tmp:$PATH" kind-app-testing.sh --force-cleanup -a ${GS_API_KEY}
          when: on_fail

workflows:
  version: 2
  build:
    jobs:
      - run_kat_tests:
          requires:
            - <add any jobs which must run first here>
          filters:
            tags:
              only: /^v.*/
```

Requirements:

* AWS:
  * IAM user with `ec2:AuthorizeSecurityGroupIngress` and `ec2:DescribeSecurityGroups`.
  * IAM user's access key & key ID must be added as environment variables to the CircleCI project. These need to be passed to the job step where `kube-app-testing.sh` is run (see example above).
  * the AWS CLI is required when testing against AWS.