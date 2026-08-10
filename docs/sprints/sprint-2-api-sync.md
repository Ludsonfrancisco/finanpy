# Sprint 2 — API privada e sincronização

Data do handoff: 2026-08-10

Branch: `codex/sprint-2-api-sync`

Base da Sprint 2: `1df25805e86ac71fbd123cb24aac818b787b9fce`

Estado: candidato à conclusão, aguardando revisão independente final.

Este documento registra somente comportamento verificado no repositório. Nenhum
deploy, comando no EasyPanel ou acesso ao banco de produção foi executado.

## Entrega verificada

- API privada versionada em `/api/v1/`, com contrato OpenAPI 3.1.0 versão 1.0.0;
- autenticação por tokens opacos vinculados a usuário, Lar e dispositivo;
- sessões revogáveis, rotação de access/refresh e revogação por reutilização de
  refresh token;
- recursos financeiros sempre filtrados pelo Lar da sessão;
- UUID e `sync_version` em contas, categorias e transações;
- captura append-only de mudanças web/API e tombstones de exclusão, inclusive
  cascade `Account -> Transaction`;
- push idempotente com controle otimista de versão e pull incremental com cursor
  assinado e vinculado ao Lar;
- logs JSON seguros, `X-Request-ID`, health check e erros JSON estáveis;
- CI com secret scan, Ruff, checks Django/deploy/migrations, warnings e coverage.

O cliente Flutter e a interface/pipeline de importação não fazem parte desta
entrega e não existem no repositório.

## Versões exatas

| Componente | Versão |
|---|---:|
| Python usado na verificação | 3.12.13 |
| Django | 5.2.13 |
| Django REST Framework | 3.17.1 |
| Gunicorn | 23.0.0 |
| Pillow | 12.2.0 |
| python-dotenv | 1.2.2 |
| asgiref | 3.11.1 |
| sqlparse | 0.5.5 |
| tzdata | 2026.1 |
| Ruff | 0.15.11 |
| Coverage.py | 7.13.5 |

## Contrato HTTP entregue

Todas as rotas, exceto health, login e refresh, exigem bearer token opaco de uma
`DeviceSession` ativa no Lar correto.

| Método | Rota | Finalidade |
|---|---|---|
| GET | `/api/v1/health/` | saúde e versão da API |
| POST | `/api/v1/auth/login/` | cria sessão e par de tokens |
| POST | `/api/v1/auth/refresh/` | rotaciona access e refresh |
| POST | `/api/v1/auth/logout/` | revoga a sessão atual |
| GET | `/api/v1/devices/` | lista dispositivos do usuário/Lar |
| PATCH | `/api/v1/devices/current/` | renomeia dispositivo/owner padrão |
| POST | `/api/v1/devices/{device_uuid}/revoke/` | revoga outro dispositivo do escopo |
| GET | `/api/v1/household/` | retorna o Lar autenticado |
| GET | `/api/v1/owners/` | lista responsáveis do Lar |
| GET | `/api/v1/accounts/` | lista contas do Lar |
| GET | `/api/v1/categories/` | lista categorias do Lar |
| GET | `/api/v1/transactions/` | lista transações do Lar |
| GET | `/api/v1/summary/` | retorna totais consolidados do Lar |
| GET | `/api/v1/bootstrap/` | snapshot inicial e cursor atual |
| POST | `/api/v1/sync/push/` | aplica lote idempotente de 1 a 100 operações |
| GET | `/api/v1/sync/changes/` | retorna até 100 mudanças depois do cursor |

O contrato normativo está em [`docs/openapi-v1.yaml`](../openapi-v1.yaml).

## Tokens e limites

- access token: 15 minutos;
- refresh token: 30 dias;
- material aleatório: `secrets.token_urlsafe(48)`;
- persistência: somente digest HMAC-SHA-256 com `SECRET_KEY`;
- refresh: access e refresh são rotacionados juntos;
- reutilização de refresh já consumido: revoga a sessão;
- login: 5 requisições por minuto por escopo do throttle;
- refresh: 30 requisições por minuto por escopo do throttle;
- push: máximo de 100 operações não vazias;
- pull: limite padrão/máximo de 100 mudanças;
- listas simples de recursos: ainda sem filtros ou paginação HTTP.

## Commits da Sprint 2 antes do handoff

| Task | Commits |
|---|---|
| 1 | `c007f92f2ffea5b911877ede4b64c687243e4f0d` |
| 2 | `76bde722c42bd2098e7ff58171516131c1498c80`, `cd78dfafa66e9db20f6a50931175017f55d96128` |
| 3 | `cda369cc0a12ba75b47acf004d3cc7270302cebb` |
| 4 | `9c09db55726356b56ff6345ad3c6c8f2303c56db`, `2cfa00670a9d450cb91fce24cd9756b704220c67` |
| 5 | `2871e0d476f100a53d977020e6e970f621b7b153`, `41550de16bd3aa65131885fdc684d0b53f209342` |
| 6 | `08e073c442583b3594612f65b49afa2aeb12de16`, `b26f0a2eb63ec277d2bfb4aaefedd2ae2194432d`, `6b2a75d431a5c82be8035e066c8ff528c130cb45` |
| 7 | `42d3a85aa37ec0aab48818156f4e48490603edd2`, `850e13cbc94f36e5a3c235759efef0189a16fb89` |
| 8 | `a52290f4190a7270ced630786541c223d449323e`, `1bb867a122bbf20b058ed601994ac2bb36aacbf4`, `97830c03ff67cb7404b3a9b32409417bc4018ae6`, `7c8ac2fc65d6c73a219a1ac474ec363e30016870`, `0c2017e50a9ba19d555bf8d8c39d0ac78f92386b` |
| 9 | `2230bc4a43c189bb6b7abb58b99b00b3d57b4f62`; follow-up neste commit, mensagem `test: start legacy rehearsal from sprint one` |

## Ensaios de migration

Todos os ensaios usaram apenas SQLite temporário: um arquivo novo em diretório
temporário e o banco SQLite temporário do test runner.

| Ensaio | Evidência |
|---|---|
| Fresh | 1 banco novo migrou as 22 migrations dos apps do projeto até todos os heads |
| Legado inicial | 2 contas, 2 categorias e 2 transações; 0 das 4 tabelas Sprint 2 presentes |
| Legado forward | o primeiro forward criou as 4 tabelas `api/sync` e migrou os 6 registros para head |
| Metadados | 6 UUIDs presentes/únicos por entidade e 6 versões iguais a 1 |
| Estado após forward | 0 sessões, 0 refresh usados, 0 operações idempotentes e 0 mudanças |
| Rollback | 1 ciclo removeu as 4 tabelas `api/sync` e os campos Sprint 2 |
| Preservação | as mesmas 6 linhas financeiras e todos os seus campos Sprint 1 permaneceram |
| Replay | 1 segundo forward voltou ao head sem sessões/mudanças residuais |
| Auditoria | 12 verificações com contagem zero; `integrity_status=ok` |

## Matriz de qualidade

- `python -Wd -W error::DeprecationWarning manage.py test`: 276 testes, 0
  falhas, 124,488 s;
- coverage: 276 testes, 5.463 statements, 96 não cobertos, 98%; gate mínimo
  de 90% aprovado;
- Ruff: 0 erros;
- `manage.py check`: 0 issues;
- `manage.py check --deploy --fail-level WARNING`: 0 issues;
- `makemigrations --check --dry-run`: nenhuma mudança;
- `git diff --check`: aprovado.

Os testes usaram `SECURE_SSL_REDIRECT=False`; os checks de produção usaram o
default seguro com `DEBUG=False`, HSTS habilitado, hosts explícitos e uma
`SECRET_KEY` efêmera.

## Rollback ensaiado e operação recomendada

O teste automatizado prova a reversibilidade do schema Sprint 2 e a preservação
das seis linhas legadas. Ele não autoriza rollback direto em produção.

1. Bloquear escritas e manter uma réplica/um worker.
2. Executar auditoria e criar backup externo; restaurá-lo em outra cópia e provar
   a restauração antes de qualquer migration real.
3. Preferir rollback operacional para imagem compatível com Sprint 1 + restauração
   do backup validado.
4. Somente em uma cópia controlada, o rollback de schema ensaiado é: `sync zero`,
   `api zero`, `transactions 0004`, `categories 0004`, `accounts 0004`.
5. Comparar contagens/snapshots das linhas Sprint 1 e executar a auditoria com a
   imagem compatível.
6. Para recuperar o forward na cópia, executar `manage.py migrate` e novamente
   `audit_household_integrity`.

## Limites conhecidos e bloqueios de produção

- **Não existe deploy automático no EasyPanel e nenhum deploy foi executado.**
- **Migration de produção está bloqueada até uma restauração de backup externo
  ser comprovada.**
- **A rotação da credencial histórica continua sendo ação do proprietário.**
- **Flutter e a UI/pipeline de importação não existem.**
- **Enquanto o banco for SQLite, operar somente uma réplica e um worker.**
- EasyPanel real, persistência após reinício, concorrência real e restauração fora
  do host não foram validados.
- Não há UI cliente para resolução de conflitos; retenção de tombstones ainda não
  foi definida.
- A conclusão da Sprint 2 e seu checkbox dependem do verdict independente final.
