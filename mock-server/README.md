# Mock backend

Node.js built-in modules only; no npm install or dependency. This is a **local mock API**, not the Rust/Windows production host.

## Run

From repository root: `npm run mock`, then open `http://127.0.0.1:4173`.

For an isolated preview only: `HOST=0.0.0.0 PORT=4173 npm run mock`. Normal run binds to loopback. The API never starts processes, reads desktop pixels, sends OS input, or accesses camera/microphone/audio devices.

## API

- `GET /api/health`, `/api/device`, `/api/windows`
- `GET/PATCH /api/settings` (allowlisted values, atomic local save)
- `GET /api/sessions/current`, `POST /api/sessions`, `DELETE /api/sessions/:id`

Session is in-memory and single-session; settings persist to ignored `.mock-data/settings.json`. No authentication is implemented because this is a local-only mock, **not safe to expose to a network**.

## Test

`npm test` runs an integration test using Node's built-in test runner.
