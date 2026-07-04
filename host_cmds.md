# Host / SSH Management

`s` → main dev box, `sfd` → secondary (e.g. a fleet host for long tests).
Both just save a `user@host` address, untracked and per-device. `sfd` also
keeps a named registry — a name passed to `s`/`sfd` resolves to its address,
otherwise it's used literally.

| Command | Action |
| :--- | :--- |
| `s` | SSH to main. |
| `s user@host` / `s name` | Set main (raw address or registered name) and connect. |
| `sfd` | SSH to secondary. |
| `sfd name` | SSH to a registered host and set it as secondary. |
| `sfd new name [user@host]` | Register a host (prompts if address omitted). |
| `sfd rm name` | Delete a registered host. |
| `sfd ls` | List hosts; `(s)` / `(dev)` mark main / secondary (`(s)` wins if both match). |
