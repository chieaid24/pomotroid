---
name: deploy
description: Deploy the pushed HEAD of this repo to this Windows PC via the CI build. Use after pushing any change here, or when the user says deploy, install the build, or update my local build.
---

The app on this PC is the installer built by the `Build` workflow (Windows x64, artifact `pomotroid-windows-x64`); nothing is compiled locally. `scripts/deploy.sh` waits for HEAD's run, downloads the installer, installs it, and relaunches the app.

1. Commit and push first; the script refuses an unpushed HEAD.
2. Run `bash scripts/deploy.sh` from the repo root. The build takes 6-10 minutes. Tell the user a UAC prompt will appear on the Windows desktop at the install step.
3. Done when the script prints `Deployed <sha>: installed and running.`

If the build fails, the script prints the failed step logs: fix, push, deploy again. If UAC was declined, rerun the script; it reuses the finished run.
