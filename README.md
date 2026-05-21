# local-proxy-zabbix

## Versao atual do proxy

O proxy esta configurado para rodar com a imagem:
- `zabbix/zabbix-proxy-mysql:alpine-7.0-latest` (definida em `docker-compose.yml`)

Banco de dados usado pelo proxy:
- `mariadb:10.11`

## Preparar um novo ambiente

Rode o script abaixo no host do proxy:

```bash
./setup-zabbix-proxy.sh \
  --server-host zabbix.exemplo.com \
  --proxy-name nome-do-proxy \
  --agent-hostname HOST-DO-PROXY \
  --psk-identity "PSK NOME-DO-PROXY" \
  --force-psk
```

Ele cria ou atualiza:

- `zabbix/env_vars/.env_prx`
- `zabbix/env_vars/.env_agent`
- `zabbix/env_vars/proxy.psk`

O parametro `--force-psk` gera uma PSK nova. Copie o valor exibido no final do script e cole no proxy correspondente no frontend do Zabbix.

Depois cadastre no frontend do Zabbix:

- Proxy name: mesmo valor de `--proxy-name`
- TLS PSK identity: mesmo valor de `--psk-identity`
- TLS PSK: conteudo de `zabbix/env_vars/proxy.psk`
- Host monitorado pelo agent: mesmo valor de `--agent-hostname`

Suba a stack:

```bash
docker compose up -d
```

Os arquivos `.env_*` e `proxy.psk` nao devem ser publicados no Git.
