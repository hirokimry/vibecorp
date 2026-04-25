{
  "permissions": {
    "allow": [
      "Write(.claude/knowledge/**)",
      "Edit(.claude/knowledge/**)",
      "Write(.claude/rules/**)",
      "Edit(.claude/rules/**)",
      "Write(.claude/plans/**)",
      "Edit(.claude/plans/**)",
      "Write(//Users/**/.cache/vibecorp/plans/**)",
      "Edit(//Users/**/.cache/vibecorp/plans/**)",
      "Write(//Users/**/.cache/vibecorp/state/**)",
      "Edit(//Users/**/.cache/vibecorp/state/**)",
      "Write(//home/**/.cache/vibecorp/plans/**)",
      "Edit(//home/**/.cache/vibecorp/plans/**)",
      "Write(//home/**/.cache/vibecorp/state/**)",
      "Edit(//home/**/.cache/vibecorp/state/**)"
    ]
  },
  "extraKnownMarketplaces": {
    "vibecorp": {
      "source": {
        "source": "github",
        "repo": "hirokimry/vibecorp"
      }
    }
  },
  "enabledPlugins": {
    "vibecorp@vibecorp": true
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-branch.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/diagnose-guard.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/role-gate.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/command-log.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-api-bypass.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sync-gate.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-branch.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/review-gate.sh"
          }
        ]
      }
    ]
  }
}
