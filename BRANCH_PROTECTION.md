# Branch Protection Setup (main)

Use this once in GitHub to protect `main` and require successful web deploy checks.

## Steps

1. Open repository settings:
   - https://github.com/coderYao/Grind-And-Chill-/settings/branches
2. Click **Add branch protection rule**.
3. Branch name pattern: `main`
4. Enable:
   - **Require a pull request before merging**
   - **Require approvals** (minimum 1)
   - **Dismiss stale pull request approvals when new commits are pushed**
   - **Require status checks to pass before merging**
5. Under required checks, select the workflow job from:
   - Workflow: `Deploy Web To Cloudflare Pages`
   - Job name: `Deploy`
6. Optional but recommended:
   - **Require branches to be up to date before merging**
   - **Require conversation resolution before merging**
   - **Include administrators**
7. Save changes.

## Practical flow after enabling

- Create feature branch.
- Open PR into `main`.
- Wait for `Deploy Web To Cloudflare Pages / Deploy` to pass.
- Merge PR.

