# Contribution guide

<!-- TOC -->
* [Contribution guide](#contribution-guide)
  * [Dev workflow](#dev-workflow)
    * [Code change checklist](#code-change-checklist)
  * [API design conventions](#api-design-conventions)
  * [Typical tasks](#typical-tasks)
    * [Working with EF Core migrations](#working-with-ef-core-migrations)
    * [Adding a new application](#adding-a-new-application)
<!-- TOC -->

This document is the a contribution guide for the AIG backend stack project. _It is a work in progress._

> Assumes that you have already followed the [dev-setup](./dev-setup.md) guide and have a working local development environment.

> **Tip** If you are new to the project, you may find it useful to read the following first:
>   * [Architecture and Project structure](./architecture-and-project-structure.md)
>   * [Branch and deployment strategy](./branch-and-deployment-strategy.md)


## Dev workflow

1. Create a feature branch either from master or from a release branch
2. Visual Studio user? Make sure to have enabled the tooling in Visual Studio (Tools>Customize>Toolbars | Application Insights)
3. Make changes and commit to feature branch following the [Code change checklist](#code-change-checklist) below   
4. Commit to feature branch, then push feature branch
5. Create a pull request (PR) from feature branch to master or release branch
6. Wait for PR to be approved and then merge
   * **tip**: typically you will perform a squish merge to keep the commit history clean
7. Delete feature branch
8. Where the release branch has been updated, you will need to merge (via a PR) the changes from release branch to master
   * **CRITICAL** you will perform a _regular merge_ so as to avoid new commits being created on the master branch 
     (other than the merge commit)
   * this merge should be performed as soon as possible after the PR is merged to release branch otherwise the AIG dev
     environment will have old code rather than the latest code from master

### Code change checklist

* Make sure changes adhere to the [API design conventions](#api-design-conventions) section below
* Where work-in-progress changes are likely to span multiple sprints, often you will need to guard your changes behind a feature flag
  * consider using the [Asp.Net Core Feature management](https://timdeschryver.dev/blog/feature-flags-in-net-from-simple-to-more-advanced)
* Where the change affects the model you will need to create an EF core migration (see section below
  [Working with EF Core migrations](#working-with-ef-core-migrations)). Typically that's changes to:
  * [Template.Shared/Model](../src/Template.Shared/Model)
  * [Template.Shared/Data/Mapping](../src/Template.Shared/Data/Mapping)

## API design conventions

1. Encapsulate logic in domain entity classes (or an ancillary validator class when you use FluentValidation)

2. Design services to be able to be composed into larger business transaction that is greater than the immediate work they are trying to perform

   * Codebase more likely to support requirement changes without having to be modified. Instead existing code can be combined into 
     different combinations (application of Open-Closed principal)
   * A single database transaction will be used to commit changes to DB. As a by-product allows for reliability patterns such as retry
     due to transient failure

3. Consider designing API endpoints to be idempotent (safe to call multiple times)

   * Simplifies consumers as they don't have to deal with non-success conditions
   * Supports reliability patterns such as retry due to transient failure

    Note: idempotent can conflict with an optimistic concurrency control strategy. For example, you more often do NOT want to allow one user to 
    overwrite the changes being made concurrently by another user. Instead you want to reject these overwrites so that the user is notified that
    the record they have been modifying is stale

4. Minimize the number of calls to the database

5. Minimize the amount of data fetched

6. Ensure sql efficient

7. Fail fast when your assumptions about the data is found to be wrong

   * Example use `Single` / `SingleOrDefault` rather than `First` / `FirstOrDefault`

8. Support async

   * Use async methods where possible/appropriate
   * Make sure to support cancellation where possible


## Typical tasks

### Working with EF Core migrations

Here are the typical commands you will need to run to generate EF Core migrations:

```pwsh
# rollback to an previous migration
dotnet ef database update Name_of_migration_to_revert_to -p src/Template.Shared -s src/DataServicesGateway.Api
```

```pwsh
# add a migration
dotnet ef migrations add Name_of_migration -p src/Template.Shared -s src/Template.Api
```

```pwsh
# remove the last migration (requires the migration NOT to exist in the db)
dotnet ef migrations remove -p src/Template.Shared -s src/Template.Api
```

```pwsh
# generate a sql script for creating or updating the database
Remove-Item -Force -ErrorAction Continue ./obj/CreateOrUpdateDb.sql
dotnet ef migrations script -i -o obj/CreateOrUpdateDb.sql -p src/Template.Shared -s src/Template.Api
```

### Adding a new application

Set guide [here](./add-application.md)
