#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${ROOT_DIR}/zabbix/env_vars"
PRX_ENV="${ENV_DIR}/.env_prx"
AGENT_ENV="${ENV_DIR}/.env_agent"
MYSQL_ENV="${ENV_DIR}/.env_prx_mysql"
PSK_FILE="${ENV_DIR}/proxy.psk"

SERVER_HOST="SEU_ZABBIX_SERVER_DNS_OU_IP"
SERVER_PORT="10051"
PROXY_NAME="zabbix-proxy-fln"
AGENT_HOSTNAME="FLN-ZABBIX-PROXY"
PSK_IDENTITY="PSK NOME-DO-PROXY"
FORCE_PSK=0
NON_INTERACTIVE=0
START_COMPOSE=1

usage() {
  cat <<'USAGE'
Uso:
  ./setup-zabbix-proxy.sh [opcoes]

Opcoes:
  --server-host HOST       DNS/IP do Zabbix Server.
  --server-port PORT       Porta do Zabbix Server. Padrao: 10051
  --proxy-name NAME        Nome do proxy cadastrado no frontend do Zabbix.
  --agent-hostname NAME    Nome do host usado para monitorar este proxy via agent.
  --psk-identity TEXT      Identidade TLS PSK cadastrada no frontend do Zabbix.
  --force-psk             Gera novamente zabbix/env_vars/proxy.psk, mesmo se ja existir.
  --no-compose            Nao sobe a stack; apenas gera/atualiza os arquivos.
  --non-interactive       Nao pergunta nada; usa os padroes e parametros informados.
  -h, --help              Mostra esta ajuda.

Exemplo:
  ./setup-zabbix-proxy.sh \
    --server-host zabbix.exemplo.com \
    --proxy-name zabbix-proxy-fln \
    --agent-hostname FLN-ZABBIX-PROXY \
    --psk-identity "PSK FLN 001"
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-host)
      SERVER_HOST="${2:?Valor ausente para --server-host}"
      shift 2
      ;;
    --server-port)
      SERVER_PORT="${2:?Valor ausente para --server-port}"
      shift 2
      ;;
    --proxy-name)
      PROXY_NAME="${2:?Valor ausente para --proxy-name}"
      shift 2
      ;;
    --agent-hostname)
      AGENT_HOSTNAME="${2:?Valor ausente para --agent-hostname}"
      shift 2
      ;;
    --psk-identity)
      PSK_IDENTITY="${2:?Valor ausente para --psk-identity}"
      shift 2
      ;;
    --force-psk)
      FORCE_PSK=1
      shift
      ;;
    --no-compose)
      START_COMPOSE=0
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opcao desconhecida: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

prompt_value() {
  local label="$1"
  local current="$2"
  local answer

  if [[ "${NON_INTERACTIVE}" == "1" || ! -t 0 ]]; then
    printf '%s' "${current}"
    return
  fi

  read -r -p "${label} [${current}]: " answer
  printf '%s' "${answer:-$current}"
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped

  mkdir -p "$(dirname "${file}")"
  touch "${file}"
  escaped="$(printf '%s' "${value}" | sed -e 's/[\/&]/\\&/g')"

  if grep -qE "^#?[[:space:]]*${key}=" "${file}"; then
    sed -i -E "s/^#?[[:space:]]*${key}=.*/${key}=${escaped}/" "${file}"
  else
    printf '\n%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

generate_psk() {
  mkdir -p "${ENV_DIR}"

  if [[ -f "${PSK_FILE}" && "${FORCE_PSK}" != "1" ]]; then
    if [[ "${NON_INTERACTIVE}" == "1" || ! -t 0 ]]; then
      echo "Mantendo PSK existente: ${PSK_FILE}"
      chmod 644 "${PSK_FILE}"
      return
    fi

    local answer
    read -r -p "A PSK ja existe. Deseja gerar uma nova? Se sim, tambem atualize no frontend do Zabbix. [s/N]: " answer
    if [[ ! "${answer}" =~ ^[SsYy]$ ]]; then
      echo "Mantendo PSK existente: ${PSK_FILE}"
      chmod 644 "${PSK_FILE}"
      return
    fi
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 > "${PSK_FILE}"
  else
    dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' > "${PSK_FILE}"
    printf '\n' >> "${PSK_FILE}"
  fi

  chmod 644 "${PSK_FILE}"
  echo "PSK gerada: ${PSK_FILE}"
}

SERVER_HOST="$(prompt_value "Host do Zabbix Server" "${SERVER_HOST}")"
SERVER_PORT="$(prompt_value "Porta do Zabbix Server" "${SERVER_PORT}")"
PROXY_NAME="$(prompt_value "Nome do proxy cadastrado no frontend do Zabbix" "${PROXY_NAME}")"
AGENT_HOSTNAME="$(prompt_value "Nome do host para monitorar este proxy via agent" "${AGENT_HOSTNAME}")"
PSK_IDENTITY="$(prompt_value "Identidade TLS PSK" "${PSK_IDENTITY}")"

generate_psk

if [[ ! -f "${MYSQL_ENV}" && -f "${MYSQL_ENV}.example" ]]; then
  cp "${MYSQL_ENV}.example" "${MYSQL_ENV}"
  echo "Env do MySQL criado a partir do exemplo: ${MYSQL_ENV}"
fi

set_env_var "${PRX_ENV}" "ZBX_SERVER_HOST" "${SERVER_HOST}"
set_env_var "${PRX_ENV}" "ZBX_SERVER_PORT" "${SERVER_PORT}"
set_env_var "${PRX_ENV}" "ZBX_HOSTNAME" "${PROXY_NAME}"
set_env_var "${PRX_ENV}" "ZBX_STARTPINGERS" "50"
set_env_var "${PRX_ENV}" "ZBX_STATSALLOWEDIP" "0.0.0.0/0"
set_env_var "${PRX_ENV}" "ZBX_CACHESIZE" "1G"
set_env_var "${PRX_ENV}" "ZBX_TLSCONNECT" "psk"
set_env_var "${PRX_ENV}" "ZBX_TLSPSKIDENTITY" "${PSK_IDENTITY}"
set_env_var "${PRX_ENV}" "ZBX_TLSPSKFILE" "/var/lib/zabbix/ssh_keys/proxy.psk"

set_env_var "${AGENT_ENV}" "ZBX_SERVER_HOST" "zabbix-proxy-mysql"
set_env_var "${AGENT_ENV}" "ZBX_PASSIVE_ALLOW" "true"
set_env_var "${AGENT_ENV}" "ZBX_PASSIVESERVERS" "0.0.0.0/0"
set_env_var "${AGENT_ENV}" "ZBX_ACTIVE_ALLOW" "true"
set_env_var "${AGENT_ENV}" "ZBX_HOSTNAME" "${AGENT_HOSTNAME}"

start_compose_and_validate() {
  if [[ "${START_COMPOSE}" != "1" ]]; then
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker nao encontrado. Rode manualmente: docker compose up -d" >&2
    return
  fi

  echo
  echo "Subindo ou recriando a stack..."
  (cd "${ROOT_DIR}" && docker compose up -d --force-recreate)

  echo "Aguardando o agent iniciar..."
  sleep 20

  local configured_hostname
  configured_hostname="$(
    cd "${ROOT_DIR}" &&
    docker compose exec -T zabbix-agent sh -lc "awk -F= '/^Hostname=/{print \$2; exit}' /etc/zabbix/zabbix_agentd.conf" 2>/dev/null || true
  )"

  if [[ "${configured_hostname}" != "${AGENT_HOSTNAME}" ]]; then
    echo "Hostname do agent ainda esta '${configured_hostname:-vazio}'. Ajustando dentro do container..."
    (
      cd "${ROOT_DIR}" &&
      docker compose exec -T -u root zabbix-agent sh -lc "sed -i -E 's/^#?[[:space:]]*Hostname=.*/Hostname=${AGENT_HOSTNAME}/' /etc/zabbix/zabbix_agentd.conf"
    )
    (cd "${ROOT_DIR}" && docker compose restart zabbix-agent)
    sleep 10
  fi

  echo
  echo "Validacao rapida:"
  (cd "${ROOT_DIR}" && docker compose ps)
  (
    cd "${ROOT_DIR}" &&
    docker compose exec -T zabbix-agent sh -lc '
      grep -E "^Hostname=" /etc/zabbix/zabbix_agentd.conf | sed "s/^/  /"
      zabbix_agentd -t agent.hostname 2>&1 | sed "s/^/  /"
      zabbix_agentd -t "zabbix.stats[,,queue]" 2>&1 | sed "s/^/  /"
    '
  )
}

start_compose_and_validate

cat <<SUMMARY

Concluido.

Env do proxy:
  ${PRX_ENV}

Env do agent:
  ${AGENT_ENV}

Arquivo PSK:
  ${PSK_FILE}

Cadastre estes valores no frontend do Zabbix:
  Nome do proxy:          ${PROXY_NAME}
  Identidade TLS PSK:     ${PSK_IDENTITY}
  Nome do host do agent:  ${AGENT_HOSTNAME}

Valor da TLS PSK. Trate como segredo e cole somente no frontend do Zabbix:
$(cat "${PSK_FILE}")

Para subir ou recriar manualmente:
  docker compose up -d
SUMMARY
