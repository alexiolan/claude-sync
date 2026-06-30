# claude-sync env — NO secrets here (safe to commit). Secrets live in ~/.config/claude-sync/ (chmod 600).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # so launchd (minimal PATH) finds restic
export RESTIC_REPOSITORY="s3:https://e3a1c008a2d27ddd5ec7f197a961c86e.r2.cloudflarestorage.com/claude-backup"
export AWS_DEFAULT_REGION="auto"
export RESTIC_PASSWORD_FILE="$HOME/.config/claude-sync/restic-pass"
[ -f "$HOME/.config/claude-sync/r2-keys.sh" ] && . "$HOME/.config/claude-sync/r2-keys.sh"
