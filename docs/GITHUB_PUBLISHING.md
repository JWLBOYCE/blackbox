# Publishing To GitHub

This repository is designed to be published without private logbook data.

## Create The Remote

With GitHub CLI installed:

```bash
gh repo create blackbox-flight-records --public --source . --remote origin --push
```

If you prefer a private repository:

```bash
gh repo create blackbox-flight-records --private --source . --remote origin --push
```

Without GitHub CLI:

1. Create a new repository on GitHub.
2. Do not initialize it with a README.
3. Add the remote:

```bash
git remote add origin git@github.com:<owner>/blackbox-flight-records.git
git push -u origin main
```

## Before Pushing

Run:

```bash
git status --short
git ls-files | rg 'sqlite|\\.db|\\.sql|LogTen|roster|\\.pdf|\\.csv' | rg -v '^Sources/OpenPilotLogbookCore/Resources/airports\\.csv$' || true
```

The second command should return no private files.

## Protect The Repository

After the first push, configure the rules in [REPOSITORY_PROTECTION.md](REPOSITORY_PROTECTION.md).

Minimum recommended settings:

- Protect `main`.
- Require pull requests.
- Require status checks.
- Require Code Owner review.
- Block force pushes.
- Block direct pushes except by maintainers.

## Inviting Contributions

Enable:

- Issues
- Discussions
- Dependabot alerts
- Secret scanning
- Push protection

Keep repository rules that reject private logbook file patterns.
