#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_VERSION="0.1.0"
SCRIPT_NAME="vps-security-bootstrap"
STATE_DIR="/var/lib/vps-security-bootstrap"
STATE_FILE="${STATE_DIR}/state.env"
SSH_MAIN_CONFIG="/etc/ssh/sshd_config"
SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSH_DROPIN_FILE="${SSH_DROPIN_DIR}/99-vps-security-bootstrap.conf"
SSH_CLOUD_INIT_FILE="${SSH_DROPIN_DIR}/50-cloud-init.conf"
LANGUAGE="en"
DRY_RUN=0
SUDO_BIN=""
CURRENT_USER="${SUDO_USER:-${USER:-root}}"
TARGET_USER=""
SSH_PORT="22"
SSH_MODE="keys"
SSH_CONFIGURED=0
REMOVE_OLD_SSH_RULE=0
UFW_ENABLED=0
FAIL2BAN_ENABLED=0
ROOT_LOGIN_POLICY="no"
PASSWORD_AUTH_POLICY="no"
REBOOT_REQUIRED=0
UPDATE_COMPLETED=0
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [[ -t 1 ]]; then
  C_RESET="$(printf '\033[0m')"
  C_BOLD="$(printf '\033[1m')"
  C_BLUE="$(printf '\033[94m')"
  C_GREEN="$(printf '\033[92m')"
  C_YELLOW="$(printf '\033[93m')"
  C_RED="$(printf '\033[91m')"
  C_CYAN="$(printf '\033[96m')"
else
  C_RESET=""
  C_BOLD=""
  C_BLUE=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_CYAN=""
fi

msg() {
  local level="$1"
  shift
  local color="$C_BLUE"

  case "$level" in
    info) color="$C_BLUE" ;;
    success) color="$C_GREEN" ;;
    warn) color="$C_YELLOW" ;;
    error) color="$C_RED" ;;
    title) color="$C_CYAN" ;;
  esac

  printf "%b%s%b %s\n" "$color" "$1" "$C_RESET" "$2"
}

print_title() {
  printf "\n%b%s%b\n" "$C_BOLD$C_CYAN" "$1" "$C_RESET"
}

txt() {
  local key="$1"

  case "$LANGUAGE:$key" in
    en:language_prompt) echo "Select interface language / Выберите язык интерфейса:" ;;
    en:language_invalid) echo "Unknown option. English will be used." ;;
    en:intro_title) echo "VPS Security Bootstrap" ;;
    en:intro_body) echo "This script helps secure a fresh VPS on Ubuntu 24.04 LTS." ;;
    en:dry_run_enabled) echo "Dry-run mode is enabled. Commands will be printed but not executed." ;;
    en:unsupported_os) echo "This script is designed for Ubuntu 24.04 LTS. Continue only if you understand the risk." ;;
    en:continue_prompt) echo "Continue?" ;;
    en:need_sudo) echo "Root privileges or passwordless sudo are required to continue." ;;
    en:checking_env) echo "Checking environment..." ;;
    en:env_ok) echo "Environment looks good." ;;
    en:update_section) echo "System updates" ;;
    en:update_explain) echo "The script will run apt update and apt upgrade -y." ;;
    en:update_now) echo "Run system updates now?" ;;
    en:update_done) echo "System update finished." ;;
    en:update_skip_resume) echo "System update was already completed before reboot. Skipping this step." ;;
    en:reboot_later_notice) echo "A reboot will be recommended later. The script will ask about it at the end." ;;
    en:root_password_section) echo "Root password" ;;
    en:root_password_prompt) echo "Change the root password now?" ;;
    en:root_password_skip) echo "Root password step skipped." ;;
    en:user_section) echo "Sudo user" ;;
    en:user_create_prompt) echo "Create or confirm a sudo user for daily administration?" ;;
    en:user_name_prompt) echo "Enter the username to create or reuse" ;;
    en:user_exists) echo "User already exists. The script will reuse it." ;;
    en:user_created) echo "User created and added to sudo group." ;;
    en:user_sudo_ensured) echo "Sudo group membership confirmed." ;;
    en:user_missing_warn) echo "No non-root admin user is set. SSH hardening options will be limited." ;;
    en:user_name_invalid) echo "Invalid username. Use lowercase letters, digits, underscores, or hyphens, and start with a letter or underscore." ;;
    en:user_create_failed) echo "User creation failed. Please try another username or fix the issue and retry." ;;
    en:user_sudo_failed) echo "Failed to grant sudo access to that user." ;;
    en:ssh_section) echo "SSH hardening" ;;
    en:ssh_prompt) echo "Configure SSH security settings?" ;;
    en:ssh_port_prompt) echo "Enter the SSH port (1024-65535)" ;;
    en:ssh_port_invalid) echo "Invalid port. Use a value from 1024 to 65535. Falling back to 22." ;;
    en:ssh_change_port) echo "Use a custom SSH port instead of 22?" ;;
    en:ssh_auth_choice) echo "Choose SSH authentication mode:" ;;
    en:ssh_auth_keys) echo "Public key only (recommended)" ;;
    en:ssh_auth_password) echo "Keep password authentication enabled" ;;
    en:ssh_pubkey_prompt) echo "Paste the public SSH key for the admin user" ;;
    en:ssh_pubkey_empty) echo "A public key is required for key-based mode." ;;
    en:ssh_target_prompt) echo "Enter the existing non-root user that should receive SSH access" ;;
    en:ssh_target_missing) echo "That user does not exist. SSH configuration will be skipped for now." ;;
    en:ssh_backup_done) echo "SSH config backup created." ;;
    en:ssh_main_written) echo "SSH settings were written directly to /etc/ssh/sshd_config." ;;
    en:ssh_cloud_init_updated) echo "Updated /etc/ssh/sshd_config.d/50-cloud-init.conf to keep PasswordAuthentication in sync." ;;
    en:ssh_dropin_removed) echo "Removed the old /etc/ssh/sshd_config.d/99-vps-security-bootstrap.conf override to avoid conflicts." ;;
    en:ssh_validate) echo "Validating SSH configuration..." ;;
    en:ssh_invalid) echo "SSH validation failed. The new config was not applied." ;;
    en:ssh_restarted) echo "SSH service restarted successfully." ;;
    en:ssh_skip) echo "SSH configuration skipped." ;;
    en:ufw_section) echo "Firewall (UFW)" ;;
    en:ufw_prompt) echo "Configure UFW firewall now?" ;;
    en:ufw_install) echo "Installing UFW if needed..." ;;
    en:ufw_done) echo "UFW is configured." ;;
    en:ufw_remove_old) echo "Remove the old SSH rule for port 22 after opening the new port?" ;;
    en:ufw_status) echo "Current UFW rules:" ;;
    en:fail2ban_section) echo "Fail2Ban" ;;
    en:fail2ban_prompt) echo "Install and configure Fail2Ban?" ;;
    en:fail2ban_done) echo "Fail2Ban is installed and configured." ;;
    en:fail2ban_invalid) echo "Fail2Ban configuration check failed. The new config was not applied cleanly." ;;
    en:fail2ban_validate) echo "Validating Fail2Ban configuration..." ;;
    en:fail2ban_status) echo "Checking Fail2Ban SSH jail status..." ;;
    en:reboot_section) echo "Reboot" ;;
    en:reboot_needed) echo "A reboot is recommended because the system reports pending restart-required changes." ;;
    en:reboot_prompt) echo "Reboot now?" ;;
    en:reboot_later) echo "Reboot skipped. Remember to restart the server later." ;;
    en:resume_found) echo "An unfinished setup after reboot was found." ;;
    en:resume_prompt) echo "Continue setup from the step after system update?" ;;
    en:resume_continue) echo "Resuming setup from the post-update step." ;;
    en:resume_reset) echo "Saved post-reboot state cleared. Starting from the beginning." ;;
    en:resume_invalid) echo "Saved post-reboot state is invalid or outdated. Starting from the beginning." ;;
    en:summary_title) echo "Summary" ;;
    en:summary_user) echo "Admin user" ;;
    en:summary_ssh_port) echo "SSH port" ;;
    en:summary_ssh_mode) echo "SSH authentication" ;;
    en:summary_ssh_mode_keys) echo "public key only" ;;
    en:summary_ssh_mode_password) echo "passwords allowed" ;;
    en:summary_root_login) echo "Root SSH login" ;;
    en:summary_password_auth) echo "Password authentication" ;;
    en:summary_ufw) echo "UFW" ;;
    en:summary_fail2ban) echo "Fail2Ban" ;;
    en:summary_enabled) echo "enabled" ;;
    en:summary_disabled) echo "disabled / unchanged" ;;
    en:summary_command) echo "Next SSH command" ;;
    en:summary_ssh_config) echo "SSH config file" ;;
    en:summary_test) echo "Open a new terminal and verify SSH access before closing the current session." ;;
    en:summary_finish) echo "Setup finished." ;;
    en:confirm_yes_default) echo "[Y/n]" ;;
    en:confirm_no_default) echo "[y/N]" ;;
    en:choice_prompt) echo "Enter your choice" ;;
    en:press_enter) echo "Press Enter to continue" ;;
    en:backup_created) echo "Backup created:" ;;
    en:install_pkg) echo "Installing package:" ;;
    en:run_cmd) echo "Running:" ;;
    en:skip_dry_run) echo "Dry-run:" ;;
    ru:language_prompt) echo "Select interface language / Выберите язык интерфейса:" ;;
    ru:language_invalid) echo "Неизвестный вариант. Будет выбран русский язык." ;;
    ru:intro_title) echo "VPS Security Bootstrap" ;;
    ru:intro_body) echo "Скрипт помогает безопасно настроить новый VPS на Ubuntu 24.04 LTS." ;;
    ru:dry_run_enabled) echo "Включен режим dry-run. Команды будут показаны, но не выполнены." ;;
    ru:unsupported_os) echo "Скрипт рассчитан на Ubuntu 24.04 LTS. Продолжайте только если понимаете риск." ;;
    ru:continue_prompt) echo "Продолжить?" ;;
    ru:need_sudo) echo "Для продолжения нужны права root или sudo без ограничений." ;;
    ru:checking_env) echo "Проверяю окружение..." ;;
    ru:env_ok) echo "Окружение подходит." ;;
    ru:update_section) echo "Обновление системы" ;;
    ru:update_explain) echo "Скрипт выполнит apt update и apt upgrade -y." ;;
    ru:update_now) echo "Запустить обновление системы сейчас?" ;;
    ru:update_done) echo "Обновление системы завершено." ;;
    ru:update_skip_resume) echo "Обновление системы уже было выполнено до перезагрузки. Этот шаг будет пропущен." ;;
    ru:reboot_later_notice) echo "Перезагрузка потребуется позже. Скрипт задаст этот вопрос в конце." ;;
    ru:root_password_section) echo "Пароль root" ;;
    ru:root_password_prompt) echo "Сменить пароль root сейчас?" ;;
    ru:root_password_skip) echo "Шаг со сменой пароля root пропущен." ;;
    ru:user_section) echo "Sudo-пользователь" ;;
    ru:user_create_prompt) echo "Создать или подтвердить sudo-пользователя для администрирования?" ;;
    ru:user_name_prompt) echo "Введите имя пользователя, которого нужно создать или использовать" ;;
    ru:user_exists) echo "Пользователь уже существует. Скрипт будет использовать его." ;;
    ru:user_created) echo "Пользователь создан и добавлен в группу sudo." ;;
    ru:user_sudo_ensured) echo "Права sudo подтверждены." ;;
    ru:user_missing_warn) echo "Не задан админ-пользователь без root. Возможности безопасной настройки SSH будут ограничены." ;;
    ru:user_name_invalid) echo "Некорректное имя пользователя. Используйте строчные буквы, цифры, подчеркивание или дефис; имя должно начинаться с буквы или подчеркивания." ;;
    ru:user_create_failed) echo "Не удалось создать пользователя. Попробуйте другое имя или исправьте проблему и повторите попытку." ;;
    ru:user_sudo_failed) echo "Не удалось выдать этому пользователю права sudo." ;;
    ru:ssh_section) echo "Защита SSH" ;;
    ru:ssh_prompt) echo "Настроить параметры безопасности SSH?" ;;
    ru:ssh_port_prompt) echo "Введите порт SSH (1024-65535)" ;;
    ru:ssh_port_invalid) echo "Некорректный порт. Используйте значение от 1024 до 65535. Будет использован 22." ;;
    ru:ssh_change_port) echo "Использовать нестандартный SSH-порт вместо 22?" ;;
    ru:ssh_auth_choice) echo "Выберите режим аутентификации SSH:" ;;
    ru:ssh_auth_keys) echo "Только публичный ключ (рекомендуется)" ;;
    ru:ssh_auth_password) echo "Оставить вход по паролю" ;;
    ru:ssh_pubkey_prompt) echo "Вставьте публичный SSH-ключ для админ-пользователя" ;;
    ru:ssh_pubkey_empty) echo "Для режима с ключом нужен публичный SSH-ключ." ;;
    ru:ssh_target_prompt) echo "Введите существующего пользователя без root, которому нужен SSH-доступ" ;;
    ru:ssh_target_missing) echo "Такой пользователь не существует. Настройка SSH пока будет пропущена." ;;
    ru:ssh_backup_done) echo "Создана резервная копия SSH-конфига." ;;
    ru:ssh_main_written) echo "SSH-настройки записаны напрямую в /etc/ssh/sshd_config." ;;
    ru:ssh_cloud_init_updated) echo "Файл /etc/ssh/sshd_config.d/50-cloud-init.conf обновлен, чтобы PasswordAuthentication не расходился с основной настройкой." ;;
    ru:ssh_dropin_removed) echo "Старый override-файл /etc/ssh/sshd_config.d/99-vps-security-bootstrap.conf удален, чтобы избежать конфликтов." ;;
    ru:ssh_validate) echo "Проверяю SSH-конфиг..." ;;
    ru:ssh_invalid) echo "Проверка SSH не прошла. Новый конфиг не применен." ;;
    ru:ssh_restarted) echo "Сервис SSH успешно перезапущен." ;;
    ru:ssh_skip) echo "Настройка SSH пропущена." ;;
    ru:ufw_section) echo "Firewall (UFW)" ;;
    ru:ufw_prompt) echo "Настроить UFW сейчас?" ;;
    ru:ufw_install) echo "При необходимости устанавливаю UFW..." ;;
    ru:ufw_done) echo "UFW настроен." ;;
    ru:ufw_remove_old) echo "Удалить старое правило для SSH-порта 22 после открытия нового порта?" ;;
    ru:ufw_status) echo "Текущие правила UFW:" ;;
    ru:fail2ban_section) echo "Fail2Ban" ;;
    ru:fail2ban_prompt) echo "Установить и настроить Fail2Ban?" ;;
    ru:fail2ban_done) echo "Fail2Ban установлен и настроен." ;;
    ru:fail2ban_invalid) echo "Проверка конфигурации Fail2Ban не прошла. Новый конфиг применить корректно не удалось." ;;
    ru:fail2ban_validate) echo "Проверяю конфигурацию Fail2Ban..." ;;
    ru:fail2ban_status) echo "Проверяю статус SSH-джейла Fail2Ban..." ;;
    ru:reboot_section) echo "Перезагрузка" ;;
    ru:reboot_needed) echo "Рекомендуется перезагрузка: система сообщает о необходимости рестарта." ;;
    ru:reboot_prompt) echo "Перезагрузить сервер сейчас?" ;;
    ru:reboot_later) echo "Перезагрузка пропущена. Не забудьте перезапустить сервер позже." ;;
    ru:resume_found) echo "Обнаружено незавершенное выполнение после перезагрузки." ;;
    ru:resume_prompt) echo "Продолжить настройку с шага после обновления системы?" ;;
    ru:resume_continue) echo "Продолжаю настройку с шага после обновления." ;;
    ru:resume_reset) echo "Сохраненное состояние после перезагрузки очищено. Запускаю сценарий с начала." ;;
    ru:resume_invalid) echo "Сохраненное состояние после перезагрузки повреждено или устарело. Запускаю сценарий с начала." ;;
    ru:summary_title) echo "Итог" ;;
    ru:summary_user) echo "Админ-пользователь" ;;
    ru:summary_ssh_port) echo "Порт SSH" ;;
    ru:summary_ssh_mode) echo "Аутентификация SSH" ;;
    ru:summary_ssh_mode_keys) echo "только публичный ключ" ;;
    ru:summary_ssh_mode_password) echo "пароли разрешены" ;;
    ru:summary_root_login) echo "Root-вход по SSH" ;;
    ru:summary_password_auth) echo "Аутентификация по паролю" ;;
    ru:summary_ufw) echo "UFW" ;;
    ru:summary_fail2ban) echo "Fail2Ban" ;;
    ru:summary_enabled) echo "включено" ;;
    ru:summary_disabled) echo "выключено / без изменений" ;;
    ru:summary_command) echo "Команда для нового SSH-подключения" ;;
    ru:summary_ssh_config) echo "Файл SSH-конфига" ;;
    ru:summary_test) echo "Откройте новый терминал и проверьте вход по SSH, прежде чем закрывать текущую сессию." ;;
    ru:summary_finish) echo "Настройка завершена." ;;
    ru:confirm_yes_default) echo "[Y/n]" ;;
    ru:confirm_no_default) echo "[y/N]" ;;
    ru:choice_prompt) echo "Введите номер" ;;
    ru:press_enter) echo "Нажмите Enter для продолжения" ;;
    ru:backup_created) echo "Создана резервная копия:" ;;
    ru:install_pkg) echo "Устанавливаю пакет:" ;;
    ru:run_cmd) echo "Выполняю:" ;;
    ru:skip_dry_run) echo "Dry-run:" ;;
    *) echo "$key" ;;
  esac
}

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--help]

Options:
  --dry-run   Print commands without executing them.
  --help      Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      printf "Unknown option: %s\n" "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

choose_language() {
  printf "%s\n" "$(txt language_prompt)"
  printf "1) English\n"
  printf "2) Русский\n"
  read -r -p "> " language_choice
  case "$language_choice" in
    1) LANGUAGE="en" ;;
    2) LANGUAGE="ru" ;;
    *)
      LANGUAGE="en"
      printf "%s\n" "$(txt language_invalid)"
      ;;
  esac
}

confirm() {
  local prompt="$1"
  local default="${2:-yes}"
  local hint=""
  local answer=""

  if [[ "$default" == "yes" ]]; then
    hint="$(txt confirm_yes_default)"
  else
    hint="$(txt confirm_no_default)"
  fi

  while true; do
    read -r -p "$prompt $hint " answer
    answer="${answer:-}"
    case "$answer" in
      [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) return 0 ;;
      [Nn]|[Nn][Oo]|[Нн]|[Нн][Ее][Тт]) return 1 ;;
      "")
        [[ "$default" == "yes" ]] && return 0 || return 1
        ;;
    esac
  done
}

prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local answer=""

  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer
    printf "%s" "${answer:-$default}"
  else
    read -r -p "$prompt: " answer
    printf "%s" "$answer"
  fi
}

run_root_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "$*"
    return 0
  fi

  msg info "$(txt run_cmd)" "$*"
  if [[ -n "$SUDO_BIN" ]]; then
    "$SUDO_BIN" "$@"
  else
    "$@"
  fi
}

backup_file() {
  local file="$1"
  if [[ -e "$file" ]]; then
    local backup="${file}.bak.${TIMESTAMP}"
    run_root_cmd cp "$file" "$backup"
    msg success "$(txt backup_created)" "$backup"
  fi
}

require_root_or_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO_BIN=""
    return 0
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO_BIN="sudo"
    return 0
  fi

  msg error "!" "$(txt need_sudo)"
  exit 1
}

check_os() {
  if [[ ! -r /etc/os-release ]]; then
    msg warn "!" "$(txt unsupported_os)"
    return
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    msg warn "!" "$(txt unsupported_os)"
    if ! confirm "$(txt continue_prompt)" "no"; then
      exit 1
    fi
  fi
}

ensure_package() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  msg info "$(txt install_pkg)" "$pkg"
  run_root_cmd apt-get install -y "$pkg"
}

update_system() {
  print_title "$(txt update_section)"
  msg info "i" "$(txt update_explain)"

  if [[ "$UPDATE_COMPLETED" -eq 1 ]]; then
    msg info "i" "$(txt update_skip_resume)"
    detect_reboot_requirement
    if [[ "$REBOOT_REQUIRED" -eq 1 ]]; then
      msg warn "!" "$(txt reboot_later_notice)"
    fi
    return 0
  fi

  if confirm "$(txt update_now)" "yes"; then
    run_root_cmd apt-get update
    run_root_cmd apt-get upgrade -y
    UPDATE_COMPLETED=1
    msg success "+" "$(txt update_done)"
  fi

  detect_reboot_requirement
  if [[ "$REBOOT_REQUIRED" -eq 1 ]]; then
    msg warn "!" "$(txt reboot_later_notice)"
  fi
}

detect_reboot_requirement() {
  if [[ -f /var/run/reboot-required || -f /run/reboot-required ]]; then
    REBOOT_REQUIRED=1
    return 0
  fi

  if ! command -v needrestart >/dev/null 2>&1; then
    return 0
  fi

  local needrestart_output=""
  if needrestart_output="$(needrestart -b 2>/dev/null)"; then
    if printf "%s\n" "$needrestart_output" | grep -Eq 'NEEDRESTART-KSTA: [23]'; then
      REBOOT_REQUIRED=1
    fi
  fi
}

maybe_change_root_password() {
  if [[ "${EUID}" -ne 0 ]]; then
    return 0
  fi

  print_title "$(txt root_password_section)"
  if confirm "$(txt root_password_prompt)" "no"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      msg warn "$(txt skip_dry_run)" "passwd root"
    else
      passwd root
    fi
  else
    msg info "-" "$(txt root_password_skip)"
  fi
}

validate_username() {
  local user_name="$1"
  [[ "$user_name" =~ ^[a-z_][a-z0-9_-]*\$?$ ]]
}

setup_admin_user() {
  print_title "$(txt user_section)"
  if ! confirm "$(txt user_create_prompt)" "yes"; then
    return 0
  fi

  local user_name=""

  while true; do
    user_name="$(prompt_input "$(txt user_name_prompt)")"

    if [[ -z "$user_name" ]]; then
      msg warn "!" "$(txt user_missing_warn)"
      return 0
    fi

    TARGET_USER="$user_name"

    if id "$TARGET_USER" >/dev/null 2>&1; then
      msg warn "!" "$(txt user_exists)"
    else
      if ! validate_username "$TARGET_USER"; then
        msg warn "!" "$(txt user_name_invalid)"
        continue
      fi

      if [[ "$DRY_RUN" -eq 1 ]]; then
        msg warn "$(txt skip_dry_run)" "adduser $TARGET_USER"
      else
        if ! run_root_cmd adduser "$TARGET_USER"; then
          msg error "!" "$(txt user_create_failed)"
          TARGET_USER=""
          continue
        fi
      fi
      msg success "+" "$(txt user_created)"
    fi

    if run_root_cmd usermod -aG sudo "$TARGET_USER"; then
      msg success "+" "$(txt user_sudo_ensured)"
      return 0
    fi

    msg error "!" "$(txt user_sudo_failed)"
    TARGET_USER=""
  done
}

pick_existing_target_user_if_needed() {
  if [[ -n "$TARGET_USER" ]]; then
    return 0
  fi

  if [[ "${EUID}" -ne 0 && "$CURRENT_USER" != "root" ]]; then
    TARGET_USER="$CURRENT_USER"
    return 0
  fi

  local selected_user
  selected_user="$(prompt_input "$(txt ssh_target_prompt)")"
  if [[ -n "$selected_user" ]] && id "$selected_user" >/dev/null 2>&1; then
    TARGET_USER="$selected_user"
  else
    msg warn "!" "$(txt ssh_target_missing)"
  fi
}

validate_port() {
  local port="$1"
  if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1024 && port <= 65535 )); then
    printf "%s" "$port"
  else
    msg warn "!" "$(txt ssh_port_invalid)"
    printf "22"
  fi
}

write_file_as_root() {
  local target_file="$1"
  local content="$2"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "write $target_file"
    return 0
  fi

  if [[ -n "$SUDO_BIN" ]]; then
    printf "%s" "$content" | "$SUDO_BIN" tee "$target_file" >/dev/null
  else
    printf "%s" "$content" >"$target_file"
  fi
}

save_resume_state() {
  local stage="$1"
  local state_content=""

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  state_content=$(
    cat <<EOF
SCRIPT_VERSION=$SCRIPT_VERSION
LANGUAGE=$LANGUAGE
CURRENT_STAGE=$stage
UPDATE_COMPLETED=$UPDATE_COMPLETED
CREATED_AT=$TIMESTAMP
EOF
  )

  run_root_cmd mkdir -p "$STATE_DIR"
  write_file_as_root "$STATE_FILE" "$state_content"
}

clear_resume_state() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  if [[ -e "$STATE_FILE" ]]; then
    run_root_cmd rm -f "$STATE_FILE"
  fi
}

wait_for_fail2ban() {
  local attempt=1

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  while (( attempt <= 5 )); do
    if [[ -n "$SUDO_BIN" ]]; then
      if "$SUDO_BIN" fail2ban-client ping >/dev/null 2>&1; then
        return 0
      fi
    else
      if fail2ban-client ping >/dev/null 2>&1; then
        return 0
      fi
    fi

    sleep 1
    attempt=$((attempt + 1))
  done

  return 1
}

set_sshd_option() {
  local file_path="$1"
  local option_name="$2"
  local option_value="$3"
  local escaped_value=""
  local sed_expr=""

  escaped_value="$(printf '%s' "$option_value" | sed 's/[\/&]/\\&/g')"
  sed_expr="s|^[#[:space:]]*${option_name}[[:space:]].*|${option_name} ${escaped_value}|"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "set ${option_name} ${option_value} in ${file_path}"
    return 0
  fi

  if [[ -n "$SUDO_BIN" ]]; then
    if "$SUDO_BIN" grep -Eq "^[#[:space:]]*${option_name}[[:space:]]+" "$file_path"; then
      "$SUDO_BIN" sed -i -E "$sed_expr" "$file_path"
    else
      printf "\n%s %s\n" "$option_name" "$option_value" | "$SUDO_BIN" tee -a "$file_path" >/dev/null
    fi
  else
    if grep -Eq "^[#[:space:]]*${option_name}[[:space:]]+" "$file_path"; then
      sed -i -E "$sed_expr" "$file_path"
    else
      printf "\n%s %s\n" "$option_name" "$option_value" >>"$file_path"
    fi
  fi
}

load_resume_state() {
  local state_key=""
  local state_value=""
  local state_script_version=""
  local state_stage=""
  local state_update_completed="0"

  if [[ ! -r "$STATE_FILE" ]]; then
    return 1
  fi

  while IFS='=' read -r state_key state_value; do
    case "$state_key" in
      SCRIPT_VERSION) state_script_version="$state_value" ;;
      CURRENT_STAGE) state_stage="$state_value" ;;
      UPDATE_COMPLETED) state_update_completed="$state_value" ;;
    esac
  done <"$STATE_FILE"

  if [[ "$state_script_version" != "$SCRIPT_VERSION" ]]; then
    return 1
  fi

  if [[ "$state_stage" != "post_update_reboot" || "$state_update_completed" != "1" ]]; then
    return 1
  fi

  return 0
}

check_resume_state() {
  if [[ "$DRY_RUN" -eq 1 || ! -e "$STATE_FILE" ]]; then
    return 0
  fi

  if ! load_resume_state; then
    msg warn "!" "$(txt resume_invalid)"
    clear_resume_state
    return 0
  fi

  msg warn "!" "$(txt resume_found)"
  if confirm "$(txt resume_prompt)" "yes"; then
    UPDATE_COMPLETED=1
    msg info "i" "$(txt resume_continue)"
    msg info "i" "$(txt update_skip_resume)"
  else
    clear_resume_state
    msg info "i" "$(txt resume_reset)"
  fi
}

configure_ssh() {
  print_title "$(txt ssh_section)"

  if ! confirm "$(txt ssh_prompt)" "yes"; then
    msg info "-" "$(txt ssh_skip)"
    return 0
  fi

  ensure_package "openssh-server"
  pick_existing_target_user_if_needed
  if [[ -z "$TARGET_USER" ]]; then
    msg warn "!" "$(txt user_missing_warn)"
    msg info "-" "$(txt ssh_skip)"
    return 0
  fi

  if confirm "$(txt ssh_change_port)" "no"; then
    SSH_PORT="$(validate_port "$(prompt_input "$(txt ssh_port_prompt)")")"
  else
    SSH_PORT="22"
  fi

  printf "\n%s\n1) %s\n2) %s\n" "$(txt ssh_auth_choice)" "$(txt ssh_auth_keys)" "$(txt ssh_auth_password)"
  local auth_choice
  auth_choice="$(prompt_input "$(txt choice_prompt)" "1")"
  local public_key=""

  if [[ "$auth_choice" == "2" ]]; then
    SSH_MODE="password"
    PASSWORD_AUTH_POLICY="yes"
  else
    SSH_MODE="keys"
    PASSWORD_AUTH_POLICY="no"
    while [[ -z "$public_key" ]]; do
      public_key="$(prompt_input "$(txt ssh_pubkey_prompt)")"
      if [[ -z "$public_key" ]]; then
        msg warn "!" "$(txt ssh_pubkey_empty)"
      fi
    done
  fi

  local home_dir
  home_dir="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  if [[ -z "$home_dir" ]]; then
    msg warn "!" "$(txt ssh_target_missing)"
    msg info "-" "$(txt ssh_skip)"
    return 0
  fi

  if [[ "$SSH_MODE" == "keys" ]]; then
    run_root_cmd install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$home_dir/.ssh"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      msg warn "$(txt skip_dry_run)" "write $home_dir/.ssh/authorized_keys"
    else
      if [[ -n "$SUDO_BIN" ]]; then
        printf "%s\n" "$public_key" | "$SUDO_BIN" tee "$home_dir/.ssh/authorized_keys" >/dev/null
        "$SUDO_BIN" chown "$TARGET_USER:$TARGET_USER" "$home_dir/.ssh/authorized_keys"
        "$SUDO_BIN" chmod 600 "$home_dir/.ssh/authorized_keys"
      else
        printf "%s\n" "$public_key" >"$home_dir/.ssh/authorized_keys"
        chown "$TARGET_USER:$TARGET_USER" "$home_dir/.ssh/authorized_keys"
        chmod 600 "$home_dir/.ssh/authorized_keys"
      fi
    fi
  fi

  backup_file "$SSH_MAIN_CONFIG"
  set_sshd_option "$SSH_MAIN_CONFIG" "Port" "$SSH_PORT"
  set_sshd_option "$SSH_MAIN_CONFIG" "PermitRootLogin" "no"
  set_sshd_option "$SSH_MAIN_CONFIG" "PubkeyAuthentication" "yes"
  set_sshd_option "$SSH_MAIN_CONFIG" "PasswordAuthentication" "$PASSWORD_AUTH_POLICY"
  set_sshd_option "$SSH_MAIN_CONFIG" "PermitEmptyPasswords" "no"
  set_sshd_option "$SSH_MAIN_CONFIG" "KbdInteractiveAuthentication" "no"
  set_sshd_option "$SSH_MAIN_CONFIG" "ChallengeResponseAuthentication" "no"
  set_sshd_option "$SSH_MAIN_CONFIG" "UsePAM" "yes"
  msg success "+" "$(txt ssh_backup_done)"
  msg info "i" "$(txt ssh_dropin_written)"

  run_root_cmd install -d -m 755 "$SSH_DROPIN_DIR"
  if [[ -f "$SSH_CLOUD_INIT_FILE" || "$DRY_RUN" -eq 1 ]]; then
    if [[ ! -f "$SSH_CLOUD_INIT_FILE" ]]; then
      write_file_as_root "$SSH_CLOUD_INIT_FILE" ""
    fi
    backup_file "$SSH_CLOUD_INIT_FILE"
    set_sshd_option "$SSH_CLOUD_INIT_FILE" "PasswordAuthentication" "$PASSWORD_AUTH_POLICY"
    msg info "i" "$(txt ssh_cloud_init_updated)"
  fi

  if [[ -e "$SSH_DROPIN_FILE" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      msg warn "$(txt skip_dry_run)" "rm -f $SSH_DROPIN_FILE"
    else
      run_root_cmd rm -f "$SSH_DROPIN_FILE"
    fi
    msg info "i" "$(txt ssh_dropin_removed)"
  fi

  msg info "i" "$(txt ssh_main_written)"

  msg info "i" "$(txt ssh_validate)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "sshd -t"
  else
    if [[ -n "$SUDO_BIN" ]]; then
      if ! "$SUDO_BIN" sshd -t; then
        msg error "!" "$(txt ssh_invalid)"
        return 1
      fi
    else
      if ! sshd -t; then
        msg error "!" "$(txt ssh_invalid)"
        return 1
      fi
    fi
  fi

  run_root_cmd systemctl restart ssh
  msg success "+" "$(txt ssh_restarted)"
  SSH_CONFIGURED=1
}

configure_ufw() {
  print_title "$(txt ufw_section)"
  if ! confirm "$(txt ufw_prompt)" "yes"; then
    return 0
  fi

  msg info "i" "$(txt ufw_install)"
  ensure_package "ufw"

  run_root_cmd ufw default deny incoming
  run_root_cmd ufw default allow outgoing
  run_root_cmd ufw allow "${SSH_PORT}/tcp" comment "SSH"
  run_root_cmd ufw allow 443/tcp comment "HTTPS"

  if [[ "$SSH_PORT" != "22" ]] && confirm "$(txt ufw_remove_old)" "no"; then
    REMOVE_OLD_SSH_RULE=1
    run_root_cmd ufw delete allow 22/tcp
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "ufw --force enable"
  else
    if ! ufw status | grep -q "Status: active"; then
      run_root_cmd ufw --force enable
    fi
  fi

  msg success "+" "$(txt ufw_done)"
  UFW_ENABLED=1
  msg info "i" "$(txt ufw_status)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "ufw status numbered"
  else
    run_root_cmd ufw status numbered
  fi
}

configure_fail2ban() {
  print_title "$(txt fail2ban_section)"
  if ! confirm "$(txt fail2ban_prompt)" "yes"; then
    return 0
  fi

  ensure_package "fail2ban"
  local jail_local="/etc/fail2ban/jail.local"
  local jail_content
  jail_content=$(
    cat <<EOF
[DEFAULT]
bantime = 2h
findtime = 30m
maxretry = 4
backend = systemd
allowipv6 = auto
usedns = no

[sshd]
enabled = true
filter = sshd
mode = normal
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
port = $SSH_PORT
EOF
  )

  backup_file "$jail_local"
  write_file_as_root "$jail_local" "$jail_content"
  msg info "i" "$(txt fail2ban_validate)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "fail2ban-client -d"
  else
    if [[ -n "$SUDO_BIN" ]]; then
      if ! "$SUDO_BIN" fail2ban-client -d >/dev/null; then
        msg error "!" "$(txt fail2ban_invalid)"
        return 1
      fi
    else
      if ! fail2ban-client -d >/dev/null; then
        msg error "!" "$(txt fail2ban_invalid)"
        return 1
      fi
    fi
  fi
  run_root_cmd systemctl enable --now fail2ban
  run_root_cmd systemctl restart fail2ban
  msg info "i" "$(txt fail2ban_status)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "$(txt skip_dry_run)" "fail2ban-client status sshd"
  else
    if ! wait_for_fail2ban; then
      msg error "!" "$(txt fail2ban_invalid)"
      return 1
    fi

    if [[ -n "$SUDO_BIN" ]]; then
      if ! "$SUDO_BIN" fail2ban-client status sshd; then
        msg error "!" "$(txt fail2ban_invalid)"
        return 1
      fi
    else
      if ! fail2ban-client status sshd; then
        msg error "!" "$(txt fail2ban_invalid)"
        return 1
      fi
    fi
  fi
  FAIL2BAN_ENABLED=1
  msg success "+" "$(txt fail2ban_done)"
}

maybe_reboot() {
  if [[ "$REBOOT_REQUIRED" -ne 1 ]]; then
    return 0
  fi

  print_title "$(txt reboot_section)"
  msg warn "!" "$(txt reboot_needed)"
  if confirm "$(txt reboot_prompt)" "no"; then
    save_resume_state "post_update_reboot"
    run_root_cmd reboot
  else
    msg warn "!" "$(txt reboot_later)"
  fi
}

bool_label() {
  local value="$1"
  if [[ "$value" == "1" || "$value" == "yes" ]]; then
    printf "%s" "$(txt summary_enabled)"
  else
    printf "%s" "$(txt summary_disabled)"
  fi
}

print_summary() {
  print_title "$(txt summary_title)"
  printf "%s: %s\n" "$(txt summary_user)" "${TARGET_USER:-${CURRENT_USER}}"
  printf "%s: %s\n" "$(txt summary_ssh_port)" "$SSH_PORT"
  if [[ "$SSH_CONFIGURED" -eq 1 && "$SSH_MODE" == "keys" ]]; then
    printf "%s: %s\n" "$(txt summary_ssh_mode)" "$(txt summary_ssh_mode_keys)"
  elif [[ "$SSH_CONFIGURED" -eq 1 ]]; then
    printf "%s: %s\n" "$(txt summary_ssh_mode)" "$(txt summary_ssh_mode_password)"
  else
    printf "%s: %s\n" "$(txt summary_ssh_mode)" "$(txt summary_disabled)"
  fi
  if [[ "$SSH_CONFIGURED" -eq 1 ]]; then
    printf "%s: %s\n" "$(txt summary_root_login)" "$ROOT_LOGIN_POLICY"
    printf "%s: %s\n" "$(txt summary_password_auth)" "$PASSWORD_AUTH_POLICY"
  else
    printf "%s: %s\n" "$(txt summary_root_login)" "$(txt summary_disabled)"
    printf "%s: %s\n" "$(txt summary_password_auth)" "$(txt summary_disabled)"
  fi
  printf "%s: %s\n" "$(txt summary_ufw)" "$(bool_label "$UFW_ENABLED")"
  printf "%s: %s\n" "$(txt summary_fail2ban)" "$(bool_label "$FAIL2BAN_ENABLED")"
  if [[ "$SSH_CONFIGURED" -eq 1 ]]; then
    printf "%s: %s\n" "$(txt summary_ssh_config)" "$SSH_MAIN_CONFIG"
  fi
  printf "%s: ssh -p %s %s@YOUR_SERVER_IP\n" "$(txt summary_command)" "$SSH_PORT" "${TARGET_USER:-${CURRENT_USER}}"
  printf "%s\n" "$(txt summary_test)"
  msg success "+" "$(txt summary_finish)"
}

main() {
  choose_language
  print_title "$(txt intro_title)"
  msg info "i" "$(txt intro_body)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    msg warn "!" "$(txt dry_run_enabled)"
  fi

  msg info "i" "$(txt checking_env)"
  require_root_or_sudo
  check_os
  check_resume_state
  msg success "+" "$(txt env_ok)"

  update_system
  maybe_change_root_password
  setup_admin_user
  configure_ssh
  configure_ufw
  configure_fail2ban
  print_summary
  clear_resume_state
  maybe_reboot
}

main "$@"
