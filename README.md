# claude-code-enhanced

Extension for Claude Code: plays a sound (and, on macOS, shows a notification banner) when Claude asks you a question, asks permission to run a tool, or has finished. Each case has its own sound.

The banner shows the project folder and the text of Claude's message: the question it is asking, the command it wants to run, or the start of its last reply. On macOS it appears as coming from Script Editor; if you don't see it, enable notifications for Script Editor in System Settings → Notifications.

| Event | When it fires | Default sound (macOS) |
|---|---|---|
| `PermissionRequest` (question) | Claude asks you a multiple-choice question | `Glass` |
| `PermissionRequest` (tool) | Claude asks permission to run a tool | `Ping` |
| `Notification` *(optional)* | Claude has been waiting for your input (~1 min idle) | `Glass` |
| `Stop` | Claude has finished responding; the banner shows the start of its reply | `Hero` |

## Prerequisites

- [Claude Code](https://claude.com/claude-code) CLI
- macOS (`afplay`, built in) or Linux (`paplay` or `aplay`). Elsewhere it falls back to the terminal bell.
- `jq` (optional but recommended: without it the banner shows generic text and both cases use the same sound)

## Setup

1. Copy the script to `~/.claude/` and make it executable:

   ```sh
   cp notify-sound.sh ~/.claude/notify-sound.sh
   chmod +x ~/.claude/notify-sound.sh
   ```

2. Add the hook to your settings. Use `~/.claude/settings.json` for all projects, or `.claude/settings.json` in a project root for that project only. If you already have a `hooks` block, merge this entry into it.

   ```json
   {
     "hooks": {
       "PermissionRequest": [
         { "hooks": [{ "type": "command", "command": "sh ~/.claude/notify-sound.sh" }] }
       ],
       "Stop": [
         { "hooks": [{ "type": "command", "command": "sh ~/.claude/notify-sound.sh" }] }
       ]
     }
   }
   ```

   To also be notified after Claude has been waiting for your input for a while, add a `Notification` entry with the same command.

3. Restart Claude Code (or run `/hooks` to check it is loaded).

Test it without Claude:

```sh
echo '{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Test question?"}]}}' | sh ~/.claude/notify-sound.sh
echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"description":"List files"}}' | sh ~/.claude/notify-sound.sh
```

## Customization

The easiest way is a config file next to the script:

```sh
cp .env.example ~/.claude/notify-sound.env
```

then edit `~/.claude/notify-sound.env`. Alternatively, set the same variables in the `env` block of `settings.json` (these take precedence over the file). Each sound takes any audio file path, or `none` to mute that event:

| Variable | Default |
|---|---|
| `CLAUDE_SOUND_QUESTION` | `/System/Library/Sounds/Glass.aiff` |
| `CLAUDE_SOUND_PERMISSION` | `/System/Library/Sounds/Ping.aiff` |
| `CLAUDE_SOUND_NOTIFY` | `/System/Library/Sounds/Glass.aiff` |
| `CLAUDE_SOUND_STOP` | `/System/Library/Sounds/Hero.aiff` |
| `CLAUDE_NOTIFY_BANNER` | `1` (set to `0` to disable the macOS banner) |

Other built-in macOS sounds are in `/System/Library/Sounds/` (Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink).

On Linux, set the sound variables, since the macOS paths don't exist there (e.g. `/usr/share/sounds/freedesktop/stereo/message.oga`).
