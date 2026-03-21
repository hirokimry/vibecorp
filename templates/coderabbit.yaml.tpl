# CodeRabbit Configuration
# https://docs.coderabbit.ai/guides/configure-coderabbit

language: {{LANGUAGE}}

reviews:
  auto_review:
    enabled: true
    drafts: false

  request_changes_workflow: true

  auto_resolve:
    enabled: true

  path_filters:
    - "!**/*.lock"

  path_instructions:
    - path: "**"
      instructions: |
        PR that corresponds to an Issue must meet all requirements of the Issue.
        Identify the Issue number from the PR description or branch name,
        and verify that all items listed in the Issue are implemented.
        If any requirements are not addressed, clearly point them out.

chat:
  auto_reply: true
