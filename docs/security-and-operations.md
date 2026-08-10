# Segurança, privacidade e operação

## Modelo de ameaça resumido

Ativos: credencial do Lar Finance, tokens, dados financeiros, arquivos importados, backups, dispositivo e servidor doméstico. Ameaças prioritárias: vazamento do repositório/log, roubo de dispositivo, acesso externo indevido, perda/corrupção do disco, import malicioso, sessão não revogada e erro de sincronização.

## Estado dos achados da Sprint 1

### Crítico pendente: rotação da credencial histórica

Os valores foram removidos dos scripts no HEAD e o CI ganhou secret scanning. Como a credencial existiu no histórico Git, ainda são necessárias estas ações externas:

- rotacionar a credencial;
- confirmar que scripts/fixtures usam somente variáveis e dados sintéticos;
- avaliar remoção do histórico Git após backup e coordenação, pois reescrever histórico é destrutivo `[INVESTIGAR autorização]`.

Não reproduzir os valores em tickets, docs ou logs.

### Resolvido no código: volume SQLite

O Compose agora monta o diretório `/app/data` e usa `SQLITE_PATH=/app/data/db.sqlite3`, com uma réplica e um worker. A configuração ainda precisa ser ensaiada no EasyPanel real com backup restaurável. PostgreSQL permanece a direção futura, não uma mudança autorizada nesta sprint.

## Controles de autenticação

- signup público desativado;
- usuário criado administrativamente;
- senha forte com validadores Django;
- access token opaco com validade de 15 minutos e refresh token opaco rotativo
  com validade de 30 dias;
- somente digests HMAC-SHA-256 dos tokens são persistidos; os valores brutos são
  devolvidos na emissão/rotação e não ficam no banco;
- lista e revogação individual de dispositivos; logout revoga a sessão atual e
  reutilização de refresh token já consumido revoga a sessão correspondente;
- throttle por escopo e cache do Django: login anônimo em `5/minute` e refresh
  em `30/minute`; não existe ainda rate limit global, compartilhado entre
  processos ou específico por conta;
- biometria protege acesso local, não substitui autenticação do servidor;
- um futuro cliente deve usar Keychain, Android Keystore ou Windows Credential
  Locker e não gravar tokens em SQLite, crash report ou clipboard permanente.

O esquema OpenAPI chama a credencial de `opaqueBearer` e não afirma que ela é
JWT. Falhas usam envelope estável com `error.code`, `error.message`,
`error.fields` e `request_id`. Entre os códigos atuais estão
`invalid_credentials`, `invalid_refresh_token`, `invalid_token`,
`expired_token`, `revoked_device`, `not_authenticated`, `invalid_cursor`,
`min_1_operation`, `max_100_operations`, `throttled` e `internal_error`. Uma
exceção não tratada pela API retorna HTTP 500 com mensagem genérica, `fields`
nulo e o mesmo request ID, sem expor o texto da exceção.

## Segurança HTTP e produção

- HTTPS obrigatório;
- `DEBUG=False`, hosts explícitos e proxy headers validados;
- cookies do fallback web `Secure`, `HttpOnly`, `SameSite` apropriado;
- HSTS após validar domínio/TLS;
- CSP, `X-Content-Type-Options`, `Referrer-Policy` e frame protection;
- CORS restrito; app nativo não justifica wildcard;
- `manage.py check --deploy` como gate;
- admin em caminho/rede restritos quando possível `[INVESTIGAR infraestrutura]`.

## Dados em repouso

- PostgreSQL protegido por rede interna e credencial exclusiva;
- volumes do servidor com permissão mínima;
- backups criptografados antes de sair do host;
- SQLite local depende da criptografia do dispositivo e, se necessário, camada adicional `[INVESTIGAR risco/pacote]`;
- descrições e valores não aparecem em logs;
- arquivo bruto segue política de retenção a decidir.

## Upload/importação segura

- validar extensão, MIME e conteúdo;
- limitar tamanho, registros e tempo de processamento;
- nomes gerados pelo servidor e armazenamento privado;
- parser sem execução de macro/fórmula;
- PDF/OCR isolado se adotado;
- CSV exportado neutraliza formula injection (`=`, `+`, `-`, `@`);
- falhas não retornam stack trace nem payload completo;
- hash antes do processamento.

## Backup 3-2-1 proporcional

- cópia primária no PostgreSQL;
- backup automatizado local separado do volume;
- cópia criptografada fora do servidor/casa `[INVESTIGAR destino]`;
- retenção diária/semanal/mensal a definir;
- teste automatizado de integridade;
- restauração ensaiada periodicamente em ambiente isolado;
- RPO/RTO iniciais `[INVESTIGAR]` após entender tolerância do usuário.

Backup só é considerado válido após restauração testada.

## Observabilidade

### Logs

Cada requisição sob `/api/v1/` gera uma linha JSON em stdout com exatamente:
`timestamp`, `level`, `service`, `request_id`, `method`, `route`, `status`,
`duration_ms`, `authenticated`, `device_uuid` e `error_code`. `device_uuid` só
recebe valor para uma sessão autenticada. O header `X-Request-ID` recebido é
repassado apenas quando parseia como UUID; ausente ou inválido, é substituído por
UUID v4. O mesmo ID volta no header da resposta e no envelope de erro.

Uma camada externa de correlação cria e devolve o ID inclusive quando
`SecurityMiddleware` encerra cedo com redirect HTTPS. O middleware de access log
permanece imediatamente depois de `SecurityMiddleware`, reutiliza o ID existente
e deriva `authenticated`/`device_uuid` somente de uma `DeviceSession` em
`request.auth`; uma sessão web por cookie não é identidade de dispositivo.

O evento não inclui query string, corpo ou headers e não inclui email, CPF,
token, saldo, valor, descrição, arquivo ou payload de provedor. Retenção,
coleta centralizada, métricas e alertas ainda não foram implantados.

Os loggers `django`, `django.request` e `django.security` usam stdout JSON seguro
com timestamp, nível, nome do logger, status e request ID. Esse formatter não
serializa mensagem, argumentos, traceback, target da requisição ou headers.
`django.server` usa um handler nulo para não criar access output paralelo; o
access log `lar_finance.api` é a única evidência de acesso da API. Registros de
`django.request` sob `/api/v1/` também são filtrados, enquanto eventos de
segurança e requisições web continuam registrados.

Falhas internas produzem ainda um evento diagnóstico JSON separado e único por
requisição, contendo request ID, tipo permitido do evento, tipo qualificado da
exceção e fingerprint estável. A fingerprint usa somente o tipo e a localização
estrutural do código; mensagem, argumentos, payload e traceback não são emitidos.
Se uma falha após o dispatch produzir resposta 5xx fora do contrato, a camada
externa a substitui pelo `ErrorEnvelope` estável com código `internal_error`.

### Métricas

- disponibilidade/latência/erros HTTP;
- conexões e espaço do banco;
- fila/duração/falha de importação;
- idade do último backup válido;
- idade da última sincronização por dispositivo sem PII;
- conflitos pendentes e taxa de duplicatas;
- tempo de abertura do cliente.

### Alertas

- serviço ou banco indisponível;
- disco/volume próximo do limite;
- backup ausente/falhando;
- importações falhando repetidamente;
- pico de autenticação inválida;
- migration falhou;
- certificado TLS próximo do vencimento.

Ferramenta self-hosted ou gratuita será escolhida no Sprint 11 `[INVESTIGAR]`.

## EasyPanel

Checklist a documentar sem segredos:

- domínio e certificado;
- container image/tag;
- variáveis e secret store;
- volumes e owners;
- PostgreSQL e rede privada;
- healthcheck e restart;
- comando de migration;
- rollback da imagem;
- retenção de logs;
- backup e restauração;
- acesso administrativo.

## Incidentes

Runbooks mínimos:

- credencial vazada;
- dispositivo perdido;
- banco corrompido/indisponível;
- importação duplicou dados;
- sync gerou conflito em massa;
- servidor doméstico offline;
- atualização precisa rollback;
- backup não restaura.

Cada runbook define detecção, contenção, recuperação, validação e registro do ocorrido.

## LGPD e privacidade

Mesmo sendo uso doméstico, aplicar minimização, finalidade, segurança, portabilidade e exclusão consciente. Se o produto for compartilhado, comercializado ou exposto a terceiros, revisar enquadramento legal e papéis de controlador/operador `[INVESTIGAR com especialista]`.

## Critérios de produção

- nenhum segredo no Git;
- HTTPS e check de deploy limpo;
- signup desativado;
- backup externo restaurado em teste;
- tokens revogáveis e armazenamento seguro;
- migrations ensaiadas;
- logs sem dados financeiros;
- healthcheck/alerta ativos;
- exportação do usuário funcionando;
- plano de rollback escrito.
