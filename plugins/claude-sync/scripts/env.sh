# claude-sync env — NO secrets here (safe to commit). Secrets live in ~/.config/claude-sync/ (chmod 600).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # so launchd (minimal PATH) finds restic
# Set by setup.sh — placeholder replaced with your real bucket URL during first-run bootstrap.
export RESTIC_REPOSITORY="s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET_NAME>"
export AWS_DEFAULT_REGION="auto"
export RESTIC_PASSWORD_FILE="$HOME/.config/claude-sync/restic-pass"
[ -f "$HOME/.config/claude-sync/r2-keys.sh" ] && . "$HOME/.config/claude-sync/r2-keys.sh"
