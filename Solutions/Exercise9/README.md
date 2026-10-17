# Exercise 9 — Jenkins Multi-Stage Pipeline (Python Flask App)

> Brief: [`Exercises/9-Jenkins-Multi-Stage-Pipeline.md`](../../Exercises/9-Jenkins-Multi-Stage-Pipeline.md)

The brief asks for a **declarative Jenkins pipeline** that runs five stages for a
sample Python Flask application: **Build → Test → Deploy → Run Application →
Test Application**. The app and the `Jenkinsfile` live in a GitHub repo
(`devops-sample-code`), Jenkins checks them out from SCM, runs the pipeline and
prints the unit-test output in the console.

This folder automates the whole thing end-to-end with one script, and reproduces
the exact console output shown in the brief's *Expected Outcome*.

---

## What the brief asks for (and where it lives here)

| Brief step | What it says | Where this solution does it |
|---|---|---|
| Step 2 | Create `python-flask-app/` with `app.py`, `requirements.txt`, `test_app.py` | [`python-flask-app/`](python-flask-app/) — verbatim from the brief |
| Step 3 | Push the app to GitHub (`devops-sample-code`) | `deploy.sh` **[2/8]** via the GitHub Contents API (idempotent) |
| Step 4–6 | Create a **Pipeline** job: *Pipeline script from SCM* → Git → repo → Script Path `Jenkinsfile` | [`job/Python-MultiStage-Pipeline-config.xml`](job/Python-MultiStage-Pipeline-config.xml), posted by `deploy.sh` **[6/8]** |
| Step 5 | Add the `Jenkinsfile` (5 stages + `post`) and push it | [`Jenkinsfile`](Jenkinsfile) — verbatim from the brief |
| Step 7 | *Build Now*, watch the stages, read the console | `deploy.sh` **[7/8]** triggers the build and verifies the console |
| Step 8 | Fix missing `python3`/`pip` by `docker exec` + `apt install ...` | [`Dockerfile.jenkins`](Dockerfile.jenkins) bakes it in (automated Step 8) |

---

## Files

| File | Purpose |
|---|---|
| `python-flask-app/app.py` | Flask app with `/` returning `Hello, Jenkins Multi-Stage Pipeline!` (from the brief) |
| `python-flask-app/requirements.txt` | `flask==2.1.2` (from the brief) |
| `python-flask-app/test_app.py` | `unittest` case hitting `/` via `app.test_client()` (from the brief) |
| `Jenkinsfile` | Declarative pipeline, 5 stages + `post` (from the brief, verbatim) |
| `Dockerfile.jenkins` | `jenkins/jenkins:lts` **+ git plugin + Pipeline plugins + python3/flask** |
| `init.groovy.d/01-create-admin.groovy` | Headless `admin`/`admin` bootstrap so the job can be driven over REST |
| `job/Python-MultiStage-Pipeline-config.xml` | The Pipeline job definition (*Pipeline script from SCM*) |
| `deploy.sh` | One-shot: repo files → image → Jenkins → job → build → verify |
| `cleanup.sh` | Removes container (and optionally volume, image, repo) |

> The stock `jenkins/jenkins:lts` image ships **zero plugins and zero Python**,
> so without the Dockerfile the job cannot clone SCM (no `git` plugin), cannot
> load a declarative pipeline (no `workflow-aggregator`), and the Test stages
> die with `python3: not found` (the exact failure the brief's Step 8 fixes by
> hand). Baking all three in makes runs repeatable.

---

## Prerequisites

* Docker running locally
* `curl`, `bash` (Git Bash on Windows)
* `GITHUB_TOKEN` **only** to create/push the repo files (a classic PAT with
  `repo` scope). Not needed if the repo already exists publicly — Jenkins
  clones it anonymously.

---

## Usage

```bash
cd Solutions/Exercise9

# Full run: push app + Jenkinsfile, build Jenkins, create job, run pipeline
GITHUB_TOKEN=<your-pat> ./deploy.sh

# Afterwards, remove everything it created
./cleanup.sh --volume          # + delete the ex9_jenkins_home volume
./cleanup.sh --volume --image  # + delete the ex9-jenkins image
```

On Windows use Git Bash (`bash.exe`), and note `deploy.sh` picks the first free
port from 8080 upward — if 8080 is taken it prints the actual Jenkins UI URL.

### Sample run

```
[1/8] Checking prerequisites
  docker: Docker version 29.6.1
  GITHUB_TOKEN: set
[2/8] Ensuring GitHub sample repo 'devops-sample-code' + app + Jenkinsfile
  owner: shreyassridhar44
  repo exists
  app.py: already up to date
  requirements.txt: already up to date
  test_app.py: already up to date
  Jenkinsfile: already up to date
  app: https://github.com/shreyassridhar44/devops-sample-code
[3/8] Preparing Jenkins (image ex9-jenkins)
  image built; UI -> 8081
[4/8] Starting Jenkins (headless admin/admin)
  container: 438377dc546b
[5/8] Waiting for Jenkins on http://localhost:8081
[6/8] Creating Pipeline job 'Python-MultiStage-Pipeline' (Pipeline script from SCM)
  job created: http://localhost:8081/job/Python-MultiStage-Pipeline
[7/8] Triggering build and waiting for the result
  trigger HTTP 201
  build #1 finished: SUCCESS
  --- stages ---
    (Declarative: Checkout SCM)
    (Build)
    (Test)
    (Deploy)
    (Run Application)
    (Test Application)
    (Declarative: Post Actions)
  --- console output (tail) ---
  | [Pipeline] }
  | [Pipeline] // stage
  | [Pipeline] }
  | [Pipeline] // withEnv
  | [Pipeline] }
  | [Pipeline] // node
  | [Pipeline] End of Pipeline
  | Finished: SUCCESS
```

---

## How it works

### 1. The repo (`devops-sample-code`)

`deploy.sh` **[2/8]** ensures the GitHub repo contains the four files the brief
pushes (`app.py`, `requirements.txt`, `test_app.py`, `Jenkinsfile`). It uses the
Contents API and **only PUTs when the remote content differs**, so re-running
`deploy.sh` does not create empty commits. (This is the same public repo Exercise
8 used — it keeps `hello-world.sh` alongside the new app files.)

### 2. The Jenkins image

`[3/8]` builds `ex9-jenkins` from `Dockerfile.jenkins`:

* `apt`: `python3 python3-pip python3-venv python3-flask` → satisfies the
  brief's Step 8 without `docker exec` gymnastics
* `jenkins-plugin-cli`: `git` (SCM checkout) + `workflow-aggregator` (declarative
  Pipeline jobs, stage steps, `post` blocks)

### 3. Headless Jenkins

`[4/8]` starts the container with `init.groovy.d` mounted, which creates
`admin`/`admin` and disables anonymous read — so the REST calls in `[6/8]`/`[7/8]`
can authenticate. `[5/8]` polls `/login` until the controller is up.

### 4. The job (Pipeline from SCM)

`[6/8]` posts `job/Python-MultiStage-Pipeline-config.xml` to `/createItem`.
That XML is the REST form of the brief's Steps 4+6 UI path:

* **Definition** → `CpsScmFlowDefinition` (*Pipeline script from SCM*)
* **SCM** → Git, repo URL, branch `*/main`
* **Script Path** → `Jenkinsfile`

A CSRF crumb is fetched first (`crumbIssuer`), and any previous job of the same
name is deleted so reruns are clean.

### 5. The pipeline itself

`[7/8]` triggers a build and polls `lastBuild` until it finishes, then prints
the executed stages and the console tail, and fails the script unless the build
is `SUCCESS` **and** the console contains `Hello, Jenkins Multi-Stage Pipeline!`.

| Stage | What runs | Evidence in console |
|---|---|---|
| Build | `echo 'Creating virtual environment and installing dependencies...'` | the echo line |
| Test | `python3 -m unittest discover -s .` | `Ran 1 test ... OK` + `Hello, Jenkins Multi-Stage Pipeline!` |
| Deploy | `mkdir -p ${WORKSPACE}/python-app-deploy` + `cp app.py` | the `mkdir`/`cp` shell trace |
| Run Application | `nohup python3 .../app.py &` + write `app.pid` | `+ echo <pid>` / `+ nohup python3 ...` |
| Test Application | `python3 test_app.py` | second `Ran 1 test ... OK` + the greeting |
| post / success | `echo 'Pipeline completed successfully!'` | the echo line, then `Finished: SUCCESS` |

The console produced by this solution matches the brief's *Expected Outcome*
block line-for-line (module timestamps, PID and git version).

---

## Verification

Run `deploy.sh` — it exits `0` only if every check below passes:

| Check | Expected |
|---|---|
| Repo contains | `app.py`, `requirements.txt`, `test_app.py`, `Jenkinsfile` |
| Job created | `http://localhost:<port>/job/Python-MultiStage-Pipeline` |
| Build result | `#1 -> SUCCESS` |
| Stages executed | Checkout SCM, Build, Test, Deploy, Run Application, Test Application, Post Actions |
| Test stage output | `Ran 1 test in 0.0xxs` / `OK` / `Hello, Jenkins Multi-Stage Pipeline!` |
| Deploy artifact | `python-app-deploy/app.py` copied inside the workspace |
| Final line | `Finished: SUCCESS` |

Manual spot-check:

```bash
# console of the latest build
curl -s -u admin:admin http://localhost:8081/job/Python-MultiStage-Pipeline/1/consoleText

# the deployed copy inside the running container
docker exec jenkins ls -l /var/jenkins_home/workspace/Python-MultiStage-Pipeline/python-app-deploy
```

---

## Deviations from the brief (and why)

| # | Brief does | This solution does | Why |
|---|---|---|---|
| 1 | Step 8: `docker exec` into Jenkins, `apt install python3/pip/venv/flask` by hand | Bakes the same packages into `Dockerfile.jenkins` | Reproducible; no manual shell work; identical end state |
| 2 | Steps 3/5: interactive `git add`/`commit`/`push` | Pushes via the GitHub Contents API, idempotently | Scriptable end-to-end; avoids no-op commits on reruns |
| 3 | Steps 4/6: click through the Jenkins UI | Posts the job's `config.xml` to `/createItem` with a CSRF crumb | Same configuration, automation-friendly; still uses the exact UI-described fields |
| 4 | Install only the Pipeline plugin | Installs `git` + `workflow-aggregator` | The stock LTS image has **no** plugins — SCM checkout and declarative pipelines both need theirs |

**Note on `requirements.txt`:** the brief's `Jenkinsfile` Build stage only
`echo`s (it does not run `pip install -r requirements.txt`), so Flask reaches the
stages via the image's `python3-flask` package — this mirrors the brief exactly
and is why the build passes out of the box. To follow the "Expected Outcome"
prose literally you can add `sh 'pip3 install -r requirements.txt'` to the Build
stage (the file is already in the repo), but the pinned `flask==2.1.2` may need
a matching `werkzeug` on newer Python; the image-based path avoids that trap.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `python3: not found` in Test stage | Image lacks Python — rebuild with the provided `Dockerfile.jenkins` (this is the brief's Step 8 failure) |
| `Selected Git installation does not exist. Using Default` | Harmless: the `git` plugin is present but no git binary is configured in Jenkins; the default works |
| Job fails with "Could not find Jenkinsfile" | `Script Path` must be exactly `Jenkinsfile` at repo root (see the job XML) |
| Port 8080 busy | `deploy.sh` auto-increments; use the printed URL (e.g. 8081) |
| Second build: Flask reloader holds port 5000 | The Run Application stage backgrounds Flask; old processes may linger in the container. Harmless (the step is fire-and-forget); clear with `docker exec jenkins pkill -f app.py` or just recreate the container |
| `GITHUB_TOKEN` errors in [2/8] | Export a PAT with `repo` scope, or pre-create the public repo and run without a token |

---

## Cleanup

```bash
./cleanup.sh              # remove the Jenkins container
./cleanup.sh --volume      # + the ex9_jenkins_home data volume
./cleanup.sh --image       # + the ex9-jenkins image
./cleanup.sh --github      # + delete devops-sample-code (DESTRUCTIVE: also
                           #   removes Exercise 8's hello-world.sh — kept on
                           #   purpose by default)
```
