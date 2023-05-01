# helm-umbrella-chart-deploy

Github action to deploy a helm umbrella chart to kubernetes

## Example end-to-end workflow

See [data-services-gateway/.github/workflows/__app-deploy.yml](https://github.com/MRI-Software/data-services-gateway/blob/master/.github/workflows/__app-deploy.yml)

## Deploying a new release of helm-umbrella-chart-deploy

1. create full semantic-version tag for current branch. EG:
   ```bash
   # Replace v1.0.2 with the new semantic version (see https://semver.org/)
   git tag v1.0.2
   git push origin v1.0.2
   ````
2. move the current major version tag (eg v1) to reference the new tag version
   ```bash
   # As required replace v1 with the current major version tagged in the repo
   git tag -d v1
   git push --delete origin v1
   git tag v1 $(git rev-parse HEAD)
   git push origin v1
   ````
3. In github
    1. publish the draft (eg v1) release, ensuring that it is NOT set as latest release
    2. create the release from the new tag created above, ensuring it IS set as latest release
