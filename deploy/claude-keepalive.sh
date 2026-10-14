#!/bin/bash
# Keep-alive probe: refresh Claude + Codex OAuth before forge jobs need them.
# Usage records are local: the public trace catalog must admit forge-infra first.
LOG="$HOME/.forge-pr/keepalive.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')
NODE=${KEEPALIVE_NODE:-/opt/homebrew/bin/node}
CLAUDE=${KEEPALIVE_CLAUDE:-/opt/homebrew/bin/claude}
CODEX=${KEEPALIVE_CODEX:-/opt/homebrew/bin/codex}
CLAUDE_MODEL=${KEEPALIVE_CLAUDE_MODEL:-sonnet}
CODEX_MODEL=${KEEPALIVE_CODEX_MODEL:-gpt-6-astra}
mkdir -p "$(dirname "$LOG")" || exit 1
RUN=$("$NODE" -e 'process.stdout.write(require("node:crypto").randomBytes(8).toString("hex"))') || exit 1
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

record_usage() {
  "$NODE" - "$1" "$2" "$3" "$4" "$RUN" "$WORK/$1.out" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const [harness, requestedModel, rc, log, run, output] = process.argv.slice(2);
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : undefined;
const events = [];
// Claude JSON can span lines. Codex prints one JSON object per line.
const text = fs.readFileSync(output, 'utf8');
try { events.push(JSON.parse(text)); }
catch {
  for (const line of text.split('\n')) {
    try { events.push(JSON.parse(line)); } catch { }
  }
}
const result = events.findLast(event => event?.type === (harness === 'claude' ? 'result' : 'turn.completed'));
const usage = result?.usage;
const event = {
  v: 1, ts: new Date().toISOString(), service: 'forge-infra', event: 'usage.recorded',
  id: crypto.createHash('sha256').update(JSON.stringify(['usage', run, harness])).digest('hex').slice(0, 16),
  run, operation: 'keepalive', harness, model: requestedModel,
  call_status: rc === '0' && !result?.is_error ? 'succeeded' : 'failed'
};
if (harness === 'claude') {
  const models = Object.keys(result?.modelUsage ?? {});
  if (models.length) event.model = models.join(',');
  else if (typeof result?.model === 'string') event.model = result.model;
}
const fields = {
  input_tokens: count(usage?.input_tokens),
  output_tokens: count(usage?.output_tokens),
  cache_read_tokens: count(harness === 'claude' ? usage?.cache_read_input_tokens : usage?.cached_input_tokens),
  cache_write_tokens: count(harness === 'claude' ? usage?.cache_creation_input_tokens : usage?.cache_write_input_tokens)
};
// Codex input includes cache reads and writes. Subtract only known counters;
// absent cache fields stay absent and do not introduce fabricated zero fields.
if (harness === 'codex' && fields.input_tokens !== undefined) {
  fields.input_tokens = count(fields.input_tokens - (fields.cache_read_tokens ?? 0) - (fields.cache_write_tokens ?? 0));
}
for (const [name, value] of Object.entries(fields)) {
  if (value !== undefined) event[name] = value;
}
event.coverage = Object.values(fields).every(value => value !== undefined) ? 'reported'
  : Object.values(fields).some(value => value !== undefined) ? 'partial' : 'unknown';
const directory = process.env.FORGE_TRACE_SPOOL || path.join(process.env.HOME, '.forge-trace');
try {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  fs.appendFileSync(path.join(directory, 'forge-infra.jsonl'), JSON.stringify(event) + '\n', { mode: 0o600 });
} catch (error) {
  fs.appendFileSync(log, `${event.ts} ${harness}: usage FAIL (${error.code ?? 'write error'})\n`);
  process.exitCode = 1;
}
JS
}

# Keep stdout for usage parsing and stderr private. Preserve the CLI exit code.
"$CLAUDE" -p --model "$CLAUDE_MODEL" --output-format json "reply with exactly: ok" > "$WORK/claude.out" 2> "$WORK/claude.err"
C_RC=$?
record_usage claude "$CLAUDE_MODEL" "$C_RC" "$LOG"
C_USAGE_RC=$?
if [ "$C_RC" -eq 0 ]; then
  echo "$TS claude: ok" >> "$LOG"
else
  echo "$TS claude: FAIL (exit $C_RC)" >> "$LOG"
fi

"$CODEX" exec --json --ephemeral --skip-git-repo-check -m "$CODEX_MODEL" "reply with exactly: ok" > "$WORK/codex.out" 2> "$WORK/codex.err"
X_RC=$?
record_usage codex "$CODEX_MODEL" "$X_RC" "$LOG"
X_USAGE_RC=$?
if [ "$X_RC" -eq 0 ]; then
  echo "$TS codex: ok" >> "$LOG"
else
  echo "$TS codex: FAIL (exit $X_RC)" >> "$LOG"
fi

# Attempt both calls even if one fails, but report trace write failures to launchd.
[ "$C_USAGE_RC" -eq 0 ] && [ "$X_USAGE_RC" -eq 0 ]
