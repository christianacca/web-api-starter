# sql-action

Github action to deploy a SQL script to Azure SQL database (cross-platform; Azure AD to authenticate to SQL)

## Example

```yaml
      - name: Azure login
        uses: azure/login@v1
        with:
          client-id: ${{ env.clientId }}
          tenant-id: ${{ env.tenantId }}
          subscription-id: ${{ env.subscriptionId }}

      - name: Deploy SQL database migration
        uses: MRI-Software/sql-action@v1
        with:
          database-name: mridevaig01
          server-name: mridevaig01eastus
          sql-file: ./out/migrate-db.sql
```

## Deploying a new release of this sql-action

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
   2. create the release (eg v1.0.2) from the new tag created above, ensuring it IS set as latest release