# aberaTech

The aberaTech iPhone app: abera.tech in an app, with features added over
time. Neb owns it. A household member signs in with their own Google account.

## Features

- **Sign in with Google.** The app opens abera.tech's sign-in in a browser
  sheet. The owner is the address abera.tech's admin allowlist names. A
  household member may sign in with any of their own Google addresses and
  gets the same view. Anyone else is told the account is not set up.
- **Requests** (household). The requests that name the person signed in,
  from Neb's Notion Tasks: the ones added here and the ones the email
  routine files from their mail within the hour. Open ones show Received or
  In progress. Finished ones show Done, or Not doing with Neb's reason, for
  30 days. + adds one with a title, details, a due date and a link. Tapping
  an open one changes it. Remove takes it off the list in one tap, and Neb's
  task list keeps it, marked removed by them.
- **Fitness.** Neb's goals from his workbook: where each stands today, the
  goal, and the forecast at the due date with its chance. His weight over
  the last 120 days. Read-only.
- **Wish list.** What Neb still wants, best first, with the price, when to
  buy, and where. Read-only.
- **Apple Health** (owner). Lose It writes Neb's weigh-ins to Apple Health.
  The app sends the last 30 days, one a day, to abera.tech/fitness each time
  it opens and when iOS wakes it for a new weigh-in. Me shows Send weigh-ins
  now and what the last send did. iOS asks once for Health access.

abera.tech holds nothing for the app but its sign-ins: the requests and the
wish list are read from and written to Notion live, and fitness is the same
report abera.tech/fitness shows. The server side is in
[neb-abera/aberaTech](https://github.com/neb-abera/aberaTech), "The aberaTech
app" in its README.

## How it fits together

```text
iPhone app ──/api/app──▶ abera.tech ──Notion API──▶ Tasks, Wish list items
                              │
                              └── fitness database ◀── weigh-ins from Apple Health
```

`Packages/AberaCore` holds the sign-in, the API client and the weigh-in sync,
with no Apple-only framework, so it builds and tests on Linux.
ASWebAuthenticationSession, HealthKit and the Keychain stay in `App`.

## Install from TestFlight

Every merge to main builds the app on GitHub's Macs, signs it with the App
Store Connect API key (secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`)
and uploads it to TestFlight (`.github/workflows/testflight.yml`,
`scripts/release.sh`). The release first makes the App ID if it is missing
and puts HealthKit on it (`scripts/asc-capabilities.mjs`). The version is the
date, and the build number is the run number.

## Build and test

On the dev box, in the pinned Swift image:

```bash
make test       # AberaCore's tests
make coverage   # with the line coverage floor
make check      # format, workflow and shell lint, coverage, and the gates
```

On a Mac with Xcode, `scripts/test-app.sh` builds the app and runs the UI
tests in the simulator. They run against abera.tech in memory (`-demo`,
`App/Demo.swift`) and the simulator's real HealthKit. CI runs both on every
pull request.

`project.yml` generates the Xcode project. After editing it, run
`scripts/xcodegen.sh` and commit the project. CI fails when they differ.
