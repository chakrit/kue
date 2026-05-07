<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

Always prefix commands with `rtk`. If RTK has a dedicated filter, it uses it. If not,
it passes through unchanged. This means RTK is safe to use by default.

Even in command chains with `&&`, use `rtk` on each command:

```bash
# Wrong
git add . && git commit -m "msg" && git push

# Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands By Workflow

### Build And Compile

```bash
rtk cargo build
rtk cargo check
rtk cargo clippy
rtk tsc
rtk lint
rtk prettier --check
rtk next build
```

### Test

```bash
rtk cargo test
rtk go test
rtk jest
rtk vitest
rtk playwright test
rtk pytest
rtk rake test
rtk rspec
rtk test <cmd>
```

### Git

```bash
rtk git status
rtk git log
rtk git diff
rtk git show
rtk git add
rtk git commit
rtk git push
rtk git pull
rtk git branch
rtk git fetch
rtk git stash
rtk git worktree
```

Git passthrough works for all subcommands, even those not explicitly listed.

### GitHub

```bash
rtk gh pr view <num>
rtk gh pr checks
rtk gh run list
rtk gh issue list
rtk gh api
```

### JavaScript And TypeScript Tooling

```bash
rtk pnpm list
rtk pnpm outdated
rtk pnpm install
rtk npm run <script>
rtk npx <cmd>
rtk prisma
```

### Files And Search

```bash
rtk ls <path>
rtk read <file>
rtk grep <pattern>
rtk find <pattern>
```

### Analysis And Debug

```bash
rtk err <cmd>
rtk log <file>
rtk json <file>
rtk deps
rtk env
rtk summary <cmd>
rtk diff
```

### Infrastructure

```bash
rtk docker ps
rtk docker images
rtk docker logs <container>
rtk kubectl get
rtk kubectl logs
```

### Network

```bash
rtk curl <url>
rtk wget <url>
```

### Meta Commands

```bash
rtk gain
rtk gain --history
rtk discover
rtk proxy <cmd>
rtk init
rtk init --global
```

## Token Savings Overview

| Category         | Commands                       | Typical Savings |
| ---------------- | ------------------------------ | --------------- |
| Tests            | vitest, playwright, cargo test | 90-99%          |
| Build            | next, tsc, lint, prettier      | 70-87%          |
| Git              | status, log, diff, add, commit | 59-80%          |
| GitHub           | gh pr, gh run, gh issue        | 26-87%          |
| Package Managers | pnpm, npm, npx                 | 70-90%          |
| Files            | ls, read, grep, find           | 60-75%          |
| Infrastructure   | docker, kubectl                | 85%             |
| Network          | curl, wget                     | 65-70%          |

Overall average: 60-90% token reduction on common development operations.
<!-- /rtk-instructions -->
