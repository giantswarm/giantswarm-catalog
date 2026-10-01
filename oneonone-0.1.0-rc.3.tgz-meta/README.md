# oneonone

Keeps recurring 1:1s on Google Calendar: finds a slot that's free for both
people, sends the invite, and moves the meeting if it's declined or left
unanswered shortly before it starts.

How it works: [docs/design.md](docs/design.md). The same core also runs as a web
service for allowlisted organizers, `oneonone serve`: [docs/service.md](docs/service.md),
deployment in [docs/deploy.md](docs/deploy.md), plan in [docs/plan/PRD.md](docs/plan/PRD.md).
If you switch from the CLI to the service, remove your launchd job first, so only one
runner manages your 1:1s.

## Setup (once)

1. **Google Cloud project.** In the Google Cloud console:
   - enable the **Google Calendar API**;
   - OAuth consent screen (Google Auth Platform): audience **Internal**. You don't
     need to declare scopes under Data access; the app asks for them at sign-in;
   - Credentials → Create OAuth client ID → **Desktop app**, and download the JSON to
     `~/.config/oneonone/credentials.json`.
2. **Build and sign in:**

   ```bash
   go build -o bin/oneonone .
   ./bin/oneonone auth
   ```

   This opens the browser and saves a refresh token to `~/.config/oneonone/token.json`.
3. **Configure:** `cp config.example.yaml config.yaml` and edit it.

## Use

```bash
./bin/oneonone plan    # read-only: shows what it would do
./bin/oneonone apply   # creates/moves events, sends invites
```

Example output:

```
1:1  PERIOD      ACTION  CURRENT           NEW                     WHY
foo  2026-10     move    Tue 06 Oct 14:00  Thu 08 Oct 13:00–13:45  declined
foo  2026-11     create  -                 Tue 03 Nov 13:00–13:45  no meeting in period yet
bar  2026-09-28  ok      Thu 01 Oct 10:00  -                       accepted
bar  2026-10-12  wait    Mon 12 Oct 09:00  -                       no reply yet
```

Run `apply` on a timer, e.g. every weekday morning, and alert on any non-zero exit.
Status 2 means the run worked but some 1:1 is **stuck** and needs you. Status 1
means an error; stuck 1:1s are still listed in that case.

To drop one occurrence, add its period to `skip` in config (e.g. `skip: ["2026-12"]`
for a monthly 1:1, or the period's start Monday for weekly and biweekly ones).
`skip` only stops new meetings; if the period already has one, it is still
managed. Deleting the event also works, but only while Google still returns
deleted events.

To end a 1:1, set `stopped: true` on it: `apply` cancels its upcoming meeting
(guests are notified) and never creates or moves one. Removing `stopped: true`
resumes booking from the next period that has no cancelled meeting; a period
whose meeting the tool cancelled stays skipped as "deleted".

What has been checked against a real calendar is listed in
[docs/design.md](docs/design.md#verified-against-a-real-calendar-2026-09-30).

## Pilot guide: unattended runs

For pilot organizers: the CLI runs on your own machine, every hour, with your own
token and config. Nothing is stored centrally and attendees install nothing.

Keep the repo, the binary and the wrapper **outside** `~/Documents`, `~/Desktop` and
`~/Downloads`: macOS privacy protection stops launchd-spawned shells from reading
them, and the job then silently does nothing. The examples below use `~/src/oneonone`.

1. **Install.**

   ```bash
   git clone git@github.com:giantswarm/oneonone.git ~/src/oneonone
   cd ~/src/oneonone
   go build -o bin/oneonone .
   ```

   The binary is `~/src/oneonone/bin/oneonone`; the steps below use that path.
2. **Shared OAuth client.** Ask Lucas for the shared `credentials.json` (the Desktop
   OAuth client) and put it in `~/.config/oneonone/`, mode 600:

   ```bash
   mkdir -p ~/.config/oneonone
   chmod 700 ~/.config/oneonone
   mv ~/Downloads/credentials.json ~/.config/oneonone/
   chmod 600 ~/.config/oneonone/credentials.json
   ```

3. **Sign in:** `./bin/oneonone auth` (browser consent, saves `token.json` next to it).
4. **Configure:** `cp config.example.yaml ~/.config/oneonone/config.yaml` and edit it.
5. **Check:** `./bin/oneonone plan -config ~/.config/oneonone/config.yaml` and read
   the table before anything runs unattended.
6. **Install the hourly job** with the wrapper [contrib/oneonone-run.sh](contrib/oneonone-run.sh),
   which runs `oneonone apply`, logs, and notifies.

   macOS (launchd). Copy [contrib/launchd/io.giantswarm.oneonone.plist](contrib/launchd/io.giantswarm.oneonone.plist)
   and replace `/Users/YOU` with your home directory everywhere. If you did not clone
   to `~/src/oneonone`, also fix the wrapper path (`ProgramArguments`) and
   `ONEONONE_BIN` (your `bin/oneonone`):

   ```bash
   cp contrib/launchd/io.giantswarm.oneonone.plist ~/Library/LaunchAgents/
   $EDITOR ~/Library/LaunchAgents/io.giantswarm.oneonone.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.giantswarm.oneonone.plist
   # to remove it:
   launchctl bootout gui/$(id -u)/io.giantswarm.oneonone
   ```

   It runs at load and then every hour while the machine is awake. If nothing runs,
   read `~/.config/oneonone/oneonone.launchd.log` (launchd's own output: a wrapper
   that could not start, a path it could not read).

   Linux (cron), one line in `crontab -e`:

   ```
   0 * * * * ONEONONE_BIN=$HOME/src/oneonone/bin/oneonone $HOME/src/oneonone/contrib/oneonone-run.sh
   ```

   (`notify-send` needs a desktop session; set `DBUS_SESSION_BUS_ADDRESS` in the
   crontab if the notification doesn't show.)
7. **Test the notification once.** Run the wrapper against a stub that exits 2, so
   no real run happens:

   ```bash
   printf '#!/bin/sh\necho "some 1:1s are stuck: 1 need a human, see WHY above" >&2\nexit 2\n' > /tmp/oneonone-stub
   chmod +x /tmp/oneonone-stub
   rm -f /tmp/oneonone-test.state   # else a repeat the same day is suppressed
   ONEONONE_BIN=/tmp/oneonone-stub ONEONONE_LOG=/tmp/oneonone-test.log \
     ONEONONE_STATE=/tmp/oneonone-test.state ./contrib/oneonone-run.sh
   ```

   A notification "oneonone: 1 1:1s stuck" should appear. On macOS, if nothing
   shows, allow notifications for **Script Editor** (what `osascript` shows up as) in
   System Settings > Notifications.

**Logs.** The wrapper appends timestamped output to `~/.config/oneonone/oneonone.log`
and, above 1 MB, moves it to `oneonone.log.1` (one generation kept). The log, its
directory and the notification state are private (mode 600/700). The wrapper's
settings are environment variables: `ONEONONE_BIN`, `ONEONONE_CONFIG`,
`ONEONONE_CREDENTIALS`, `ONEONONE_TOKEN`, `ONEONONE_LOG`, `ONEONONE_LOG_MAX`,
`ONEONONE_STATE`, `ONEONONE_NOTIFY` (one executable, called with the message) and
`ONEONONE_ARGS` (extra flags for `apply`; split on spaces, so no spaces inside
values; use the path variables for paths). See the top of the script. Its exit
status is `oneonone`'s. Test the wrapper with `sh contrib/oneonone-run_test.sh`.

**The notification** fires on any non-zero exit. "oneonone: N 1:1s stuck, see log"
means exit status 2: the run worked but N 1:1s need you (for example no free slot,
a failed lookup, or the move limit reached; see [docs/design.md](docs/design.md)).
The WHY column in the log says why. "oneonone failed (exit N: <first error line>), see log" is an error
(exit 1, or 127 when the binary is not found), with the stuck count added if some
1:1s were also stuck. The same problem is not shown again the same day (numbers in
the error, such as an IP address or port that changes every run, don't make it a new
problem; that includes HTTP status codes, so a 502 and a 503 with otherwise the same
text count as one), and a successful run resets that, so a problem that persists reminds you once a day, not
hourly. If the log says "another oneonone apply is running", a previous run hung:
find it with `pgrep -fl oneonone` and stop it.

**Stopping a 1:1.** Mark it `stopped: true` in your config: its upcoming meeting is
cancelled (guests are notified) and no new ones are booked. Remove the line to resume,
from the next period that has no cancelled meeting.

**Pair coordination.** Agree with the other pilot organizers who books which pair, so
no pair gets two 1:1s. If it happens anyway, the WHY column says "1 more 1:1 in
this period, check for a duplicate"; the one who didn't agree to organize that pair
stops theirs.

## Develop

```bash
go test ./...
```

The scheduling logic in `internal/schedule` is pure and covered by tests.
`internal/gcal` is the thin Google adapter.
