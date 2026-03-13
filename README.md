# vps-security-bootstrap

[Русская версия README](./README.ru.md)

A simple interactive Bash script for basic VPS security setup.

Right now this script is made for Ubuntu 24.04 LTS.

It starts with a language choice (`English / Русский`) and then helps with updates, sudo user setup, SSH hardening, UFW, and optional Fail2Ban installation.

## What it can do

- update the system
- help create a sudo user
- configure SSH
- change the SSH port
- set up UFW
- install and configure Fail2Ban
- show a final summary with the SSH command you should test

## Quick start

Connect to your fresh VPS and run the script with a single pasted command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/4esyn/vps-security-bootstrap/main/setup-vps-security.sh)
```

This quick start assumes `bash` and `curl` are available on the server, which is a reasonable default for Ubuntu 24.04 VPS images.

If the script updates the system, asks for a reboot, and you reboot the server, run the same command again after reconnecting. The script will detect the saved state and offer to continue from the step after system update.

## Dry Run

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/4esyn/vps-security-bootstrap/main/setup-vps-security.sh) --dry-run
```

## Run from a local copy

If you already cloned the repository or copied the script to the server, run:

```bash
chmod +x setup-vps-security.sh
./setup-vps-security.sh
```

Dry-run from a local copy:

```bash
./setup-vps-security.sh --dry-run
```

## What the script does

- Updates the system with `apt update` and `apt upgrade -y`.
- Detects whether a reboot is recommended and asks before restarting the server.
- Optionally changes the `root` password when launched with root access.
- Creates or reuses a non-root admin user and ensures sudo access.
- Configures SSH directly in `/etc/ssh/sshd_config` and syncs password auth in `/etc/ssh/sshd_config.d/50-cloud-init.conf` when present.
- Supports either key-only SSH access or keeping password authentication enabled.
- Configures UFW with a safe order for SSH port changes.
- Installs and configures Fail2Ban with a local config file.
- Prints a final summary with the connection command to test in a new terminal.

## What the script changes

- Installs packages when needed: `openssh-server`, `ufw`, `fail2ban`.
- Writes SSH settings to `/etc/ssh/sshd_config`.
- Writes Fail2Ban settings to `/etc/fail2ban/jail.local`.
- Creates timestamped backups before overwriting known config files.
- Creates `~/.ssh/authorized_keys` for the selected admin user when key-based SSH is chosen.

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
