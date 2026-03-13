# vps-security-bootstrap

[Русская версия README](./README.ru.md)

`vps-security-bootstrap` is an interactive Bash script for the first security pass on a fresh VPS. Version `v1` targets `Ubuntu 24.04 LTS`, while the repository structure is intentionally generic so other operating systems can be added later.

The script starts with a language selector (`English / Русский`) and then walks the operator through system updates, sudo user creation, SSH hardening, UFW firewall setup, and optional Fail2Ban installation.

## What the script does

- Updates the system with `apt update` and `apt upgrade -y`.
- Detects whether a reboot is recommended and asks before restarting the server.
- Optionally changes the `root` password when launched with root access.
- Creates or reuses a non-root admin user and ensures sudo access.
- Configures SSH using a dedicated drop-in file in `/etc/ssh/sshd_config.d/`.
- Supports either key-only SSH access or keeping password authentication enabled.
- Configures UFW with a safe order for SSH port changes.
- Installs and configures Fail2Ban with a local config file.
- Prints a final summary with the connection command to test in a new terminal.

## What the script changes

- Installs packages when needed: `openssh-server`, `ufw`, `fail2ban`.
- Writes SSH settings to `/etc/ssh/sshd_config.d/99-vps-security-bootstrap.conf`.
- Writes Fail2Ban settings to `/etc/fail2ban/jail.local`.
- Creates timestamped backups before overwriting known config files.
- Creates `~/.ssh/authorized_keys` for the selected admin user when key-based SSH is chosen.

## Quick start

Clone or copy the script to your server, then run:

```bash
chmod +x setup-vps-security.sh
./setup-vps-security.sh
```

You can preview the workflow without making changes:

```bash
./setup-vps-security.sh --dry-run
```

## Questions the script asks

- Which language to use for the interface.
- Whether to update the system now.
- Whether to change the `root` password.
- Whether to create or reuse an admin sudo user.
- Whether to configure SSH, change the SSH port, and use key-only or password-enabled auth.
- Whether to configure UFW now.
- Whether to install and configure Fail2Ban.
- Whether to reboot if the system reports that a reboot is recommended.

## Safety notes

- Test the new SSH connection in a second terminal before closing the current session.
- If you switch SSH to key-only mode, make sure the provided public key is correct.
- If you move SSH to a custom port, the script opens the new port before offering to remove the old port 22 rule.
- The script validates the SSH configuration with `sshd -t` before restarting the service.
- The current release is designed for Ubuntu 24.04 LTS. Running it elsewhere is possible, but unsupported.

## Suggested repository contents

- `setup-vps-security.sh` - interactive bootstrap script
- `README.md` - English documentation
- `README.ru.md` - Russian documentation
- `.gitignore`
- `LICENSE` - MIT license

## License

This repository currently includes the [MIT License](./LICENSE). If you prefer to keep the repository without an open-source license later, remove or replace that file intentionally before publishing.
