# Contributing

Thanks for your interest in `tfe-management`. The repository is public and anyone can open an issue or a pull request, but it is a personal project and I review and validate every contribution myself, so please be patient.

## Before you start

- For anything bigger than a typo or a small fix, please **open an issue first** and describe what you want to change and why. It saves you time if the change doesn't fit the scope of the repository.
- Check the existing issues and pull requests to avoid duplicates.
- Never post credentials, tokens, tenant or subscription IDs, organization names or any other real value from your environment, not even in logs. Use placeholders such as `<organization_name>` or `<tenant_id>`.

## Branches

This repository has one branch per scenario (`main`, `multi-provider-azure-dynamic-credentials` and `single-provider-azure-static-credentials`), each with its own README. Open your pull request against the branch your change applies to, and say which one in the description. A change that affects several scenarios needs one pull request per branch.

## Pull request process

1. Fork the repository and create a branch from the right base branch.
2. Keep the pull request focused on one topic.
3. Run `terraform fmt` on the files you touched and `terraform validate` on the configuration.
4. Update the README (and the module README, if it applies) when you change inputs, outputs, behavior or values users have to replace.
5. Use placeholders instead of real values, and don't commit `.tfvars` files, state files or certificates from your own environment.
6. Fill in the pull request template.

I will review it when I can. A pull request may get change requests, may take a while, or may be declined if it doesn't fit the goals of the repository. There is no guaranteed response time and merging is not guaranteed.

## Issues

Please use the issue templates and include the Terraform, provider and HCP Terraform / TFE versions you use, the branch or module involved, and the steps to reproduce the problem (with secrets removed).

## Code of conduct

Be respectful and constructive. Harassment or abusive comments will be removed and may lead to being blocked.

## License

By contributing you agree that your contribution is licensed under the [Mozilla Public License 2.0](../LICENSE), the same license as the repository.
