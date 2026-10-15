#!/bin/sh
# Claude Code hook: plays a sound (and shows a macOS banner) when Claude needs
# your input or finishes a turn.
#
# Hook events handled (read from the JSON on stdin):
#   Notification      -> Claude has been waiting for your input
#   PermissionRequest -> Claude asks permission to run a tool, or asks you a question
#   Stop              -> Claude has finished responding
# The banner shows the text of Claude's message (question, command, or last reply).
#
# Settings (env vars):
#   CLAUDE_SOUND_QUESTION    audio file or "none"  (default: Glass)
#   CLAUDE_SOUND_PERMISSION  audio file or "none"  (default: Ping)
#   CLAUDE_SOUND_NOTIFY      audio file or "none"  (default: Glass)
#   CLAUDE_SOUND_STOP        audio file or "none"  (default: Hero)
#   CLAUDE_NOTIFY_BANNER  1 to show a macOS notification banner, 0 to disable (default: 1)
# They can also be set in notify-sound.env next to this script (see .env.example);
# variables already set in the environment take precedence over the file.

env_file="$(dirname "$0")/notify-sound.env"
if [ -f "$env_file" ]; then
  env_question="$CLAUDE_SOUND_QUESTION"
  env_permission="$CLAUDE_SOUND_PERMISSION"
  env_notify="$CLAUDE_SOUND_NOTIFY"
  env_stop="$CLAUDE_SOUND_STOP"
  env_banner="$CLAUDE_NOTIFY_BANNER"
  . "$env_file"
  CLAUDE_SOUND_QUESTION="${env_question:-$CLAUDE_SOUND_QUESTION}"
  CLAUDE_SOUND_PERMISSION="${env_permission:-$CLAUDE_SOUND_PERMISSION}"
  CLAUDE_SOUND_NOTIFY="${env_notify:-$CLAUDE_SOUND_NOTIFY}"
  CLAUDE_SOUND_STOP="${env_stop:-$CLAUDE_SOUND_STOP}"
  CLAUDE_NOTIFY_BANNER="${env_banner:-$CLAUDE_NOTIFY_BANNER}"
fi

input=$(cat)

field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
  fi
}

if command -v jq >/dev/null 2>&1; then
  event=$(field '.hook_event_name')
else
  event=$(printf '%s' "$input" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# Allow forcing the event from the command line: notify-sound.sh Stop
[ -n "$1" ] && event="$1"

case "$event" in
  Notification)
    # Permission prompts are already announced instantly by PermissionRequest
    [ "$(field '.notification_type')" = "permission_prompt" ] && exit 0
    sound="${CLAUDE_SOUND_NOTIFY:-/System/Library/Sounds/Glass.aiff}"
    message=$(field '.message')
    message="${message:-Claude needs your input}"
    ;;
  PermissionRequest)
    # Fires both for tool permission prompts and for AskUserQuestion questions
    tool=$(field '.tool_name')
    if [ "$tool" = "AskUserQuestion" ]; then
      sound="${CLAUDE_SOUND_QUESTION:-/System/Library/Sounds/Glass.aiff}"
      message=$(field '.tool_input.questions[0].question')
      message="${message:-Claude has a question for you}"
    else
      sound="${CLAUDE_SOUND_PERMISSION:-/System/Library/Sounds/Ping.aiff}"
      detail=$(field '.tool_input.description // .tool_input.command // .tool_input.file_path // .tool_input.url')
      message="${tool:-Tool}: ${detail:-permission needed}"
    fi
    ;;
  Stop)
    sound="${CLAUDE_SOUND_STOP:-/System/Library/Sounds/Hero.aiff}"
    # Banner text: Claude's last reply, from the hook input or the transcript
    message=$(field '.last_assistant_message')
    transcript=$(field '.transcript_path')
    if [ -z "$message" ] && [ -f "$transcript" ]; then
      message=$(tail -n 200 "$transcript" | jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // empty' 2>/dev/null)
    fi
    message="${message:-Claude has finished}"
    ;;
  *) exit 0 ;;
esac

play() {
  if command -v afplay >/dev/null 2>&1; then
    afplay "$1"                                   # macOS
  elif command -v paplay >/dev/null 2>&1 && [ -f "$1" ]; then
    paplay "$1"                                   # Linux (PulseAudio/PipeWire)
  elif command -v aplay >/dev/null 2>&1 && [ -f "$1" ]; then
    aplay -q "$1"                                 # Linux (ALSA)
  else
    printf '\a' > /dev/tty 2>/dev/null            # Fallback: terminal bell
  fi
}

# Bundle id of the app Claude Code runs in (terminal or IDE), so clicking the
# banner brings it to the front. macOS sets __CFBundleIdentifier for processes
# launched from an app; TERM_PROGRAM is the fallback.
host_app() {
  if [ -n "$__CFBundleIdentifier" ]; then
    printf '%s' "$__CFBundleIdentifier"
    return
  fi
  case "$TERM_PROGRAM" in
    Apple_Terminal) printf 'com.apple.Terminal' ;;
    iTerm.app)      printf 'com.googlecode.iterm2' ;;
    vscode)         printf 'com.microsoft.VSCode' ;;
    WarpTerminal)   printf 'dev.warp.Warp-Stable' ;;
    ghostty)        printf 'com.mitchellh.ghostty' ;;
  esac
}

banner() {
  cwd=$(field '.cwd')
  cwd="${cwd:-$PWD}"
  project=$(basename "$cwd")
  # Strip quotes/backslashes and markdown markup, flatten newlines, and keep it
  # short enough for a banner
  clean() { printf '%s' "$1" | tr -d '"\\*`#' | tr '\n' ' ' | tr -s ' ' | cut -c1-200; }
  text=$(clean "$1")

  if command -v terminal-notifier >/dev/null 2>&1; then
    app=$(host_app)
    set -- -title "Claude Code" -subtitle "$project" -message "$text" \
      -group "claude-code-$(field '.session_id')"
    case "$app" in
      com.jetbrains.*)
        # Open the project folder: the IDE focuses that project's window
        quoted_cwd="'$(printf '%s' "$cwd" | sed "s/'/'\\\\''/g")'"
        set -- "$@" -execute "open -b $app $quoted_cwd" ;;
      ?*)
        set -- "$@" -activate "$app" ;;
    esac
    # Fails (exit 3) if notifications are not allowed for terminal-notifier
    terminal-notifier "$@" && return
  fi
  if command -v osascript >/dev/null 2>&1; then
    # Fallback: clicking this banner opens Script Editor, not the terminal/IDE
    osascript -e "display notification \"$text\" with title \"Claude Code\" subtitle \"$(clean "$project")\""
  fi
}

# Run in the background so the hook returns immediately
[ "$sound" != "none" ] && play "$sound" >/dev/null 2>&1 &
[ "${CLAUDE_NOTIFY_BANNER:-1}" = "1" ] && banner "$message" >/dev/null 2>&1 &

exit 0
