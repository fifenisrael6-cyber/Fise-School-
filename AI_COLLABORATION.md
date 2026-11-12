# AI collaboration and change-control policy

## Purpose
This repository is exclusively for Fise School. Keep it independent from TYRA AI and Market Fise. Do not copy code, credentials, database configuration, migrations, or deployment settings between projects.

## Agents and responsibilities
- ChatGPT: task coordinator; clarify scope, inspect evidence, prepare acceptance criteria, and summarize review results. GitHub's ChatGPT repository connector is read-oriented; use an authorized coding agent for repository writes.
- OpenAI Codex: primary implementation agent for explicitly assigned tasks.
- Claude Code: independent architecture and regression review; may propose changes only on its own branch.
- Gemini: independent review and test-gap analysis.
- GitHub Copilot: inline assistance, PR summary, and supplementary review.

Agent availability depends on separately authorizing each GitHub app/agent and the applicable plan, quota, and credentials. This file does not grant access or configure billing.

## Mandatory approval workflow
1. Work only on a task explicitly described in a GitHub issue or approved request.
2. Create a task-specific branch from the current `main`; never commit directly to `main`.
3. Keep each agent's work isolated in its own branch. Do not have multiple agents edit the same branch or file concurrently.
4. Open a draft pull request targeting `main`. Explain the reason, exact scope, files changed, tests run, risks, and rollback considerations.
5. Run relevant checks and request independent reviews. Resolve all critical/high findings.
6. Stop and wait for the repository owner's explicit approval. Never merge, enable auto-merge, deploy, publish a release, or trigger a production migration automatically.
7. If approval is not explicit, leave the PR open and unmerged.

## Fise School non-negotiable safeguards
- Read existing code, schema, migrations, and project instructions before changing anything. Ask for missing context instead of guessing.
- Change only the requested scope. Do not remove or silently disable existing features.
- Preserve Drift local database and offline-first behavior.
- Never disable Supabase Row Level Security (RLS), weaken policies, or bypass authorization.
- Use only verified existing Supabase tables, columns, functions, and packages. Do not invent schema elements.
- Database changes must be additive and non-destructive unless the owner explicitly approves a reviewed migration plan.
- Never put service-role keys, API keys, passwords, tokens, or other secrets in Flutter code, commits, logs, issues, or PRs. Use GitHub Actions secrets or the relevant secret manager.
- Do not deploy Supabase migrations/functions, alter production data, change payment settings, or run a production build/release without explicit approval.
- Keep all Fise School work inside this repository and its own Supabase project.

## Expected validation
For Flutter changes, use the repository's existing toolchain and run, where applicable:
- `flutter pub get`
- `flutter analyze`
- relevant targeted tests, then `flutter test` when feasible

For Supabase changes, inspect migration diffs and RLS policies; validate locally first. Never treat a successful code review as authorization to deploy.

## PR checklist
- [ ] Scope matches the approved task only.
- [ ] No unrelated files or features changed.
- [ ] Drift/offline behavior preserved.
- [ ] RLS and authorization preserved.
- [ ] No secrets committed.
- [ ] Tests and analysis results included.
- [ ] Independent review findings addressed.
- [ ] Owner approval received before merge or deployment.
