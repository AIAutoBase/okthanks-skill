# Third-party notices

## Open Steps: `skills/os-*`, `docs/open-steps-routing-block.md`

- Author: Pavlo Kharmanskyi, https://github.com/kharmanskyi
- Source: https://github.com/kharmanskyi/open-steps and https://opensteps.ai
- Version copied: 0.4.8 (commit `4fa744b`)
- License: MIT, full text in [`third_party/open-steps/LICENSE`](third_party/open-steps/LICENSE)

The nine `os-*` skill folders (`SKILL.md`, `references/`, `scripts/`) and the
routing block are copied **unmodified**. Only the skills are bundled here; the
upstream plugin also ships hooks, an output style, evals and an install-check
command. Install the full plugin from upstream if you want those:

```
/plugin marketplace add kharmanskyi/open-steps
/plugin install open-steps@open-steps
```

If both the plugin and this bundle are installed, delete the `skills/os-*`
copies from `~/.claude/skills/` to avoid duplicate skill names.
