# Contributing

If you are using a GUI, steps should be identical but commands obviously different.

Overview
- Clone/pull the project
- Create a branch that corresponds to your issue number (eg. `issue-123-something`)
- Make your changes
- Push your remote branch to GitHub
- Create a pull request from your branch to `main`
- Repeat

## Creating a new branch for your issue

Create a new branch for your issue:

```bash
git checkout -b issue-123-something
```

## Making changes

Make as many commits as you like. eg.

```bash
git add some-file.py
git commit -m "some changes"
# more changes...
git add some-file.py
git commit -m "more changes"
# later...
git add .
git commit -m "complete issue 123"
```

## Push your changes

```bash
git push origin HEAD
```

`HEAD` *should* be an alias for the current branch you are on. If you are not sure just replace HEAD with the name of your branch.

```bash
git push origin issue-123-something
```

## Create a pull request

Open GitHub and create a pull request from your branch to `main`.

When you open the GitHub repo, you should be prompted to create a pull request already. If not, click Pull Requests > New Pull Request. Then, make sure it shows something like `base:main` and `compare:issue-123-something`. That means you want to merge issue-123-something into main. Then press Create Pull Request. 

If you add `#123` into the description of the PR it will try and associate the PR with your issue in GH Projects.

## Start over with your next issue(s)

```bash
git checkout main # go back to main branch
git pull origin main # get the new changes from gh
git branch -d issue-123-something # optional.. deletes the old branch from your computer
git checkout -b issue-456-something # create and switch to a new branch
# ... make your changes and push ...
```
