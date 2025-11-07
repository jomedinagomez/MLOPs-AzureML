# GitHub Instructions

Guidance files in this directory are consumed by tooling (Azure or Copilot extensions) to provide repo-specific rules. Modify these only when updating automation behavior, and keep content in sync with workflows under `../workflows`.

## Copilot Behavior Configuration

**Code Modification Policy:**
- Do NOT modify files unless explicitly requested by the user
- If the user asks for an explanation, description, or example, provide information in chat only—do not write or edit files
- Only perform file modifications when the user clearly asks for code to be written or changed
- Always confirm intent before making changes if the request is ambiguous
- Always examine actual code and Terraform configuration before answering questions or making recommendations

**When solving problems:**
- Check the actual code and configuration files in the workspace first
- Provide context-aware solutions based on existing patterns in the codebase
