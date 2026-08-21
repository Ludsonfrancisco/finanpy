# Segurança, privacidade e operação

## Modelo de ameaça resumido

Ativos: credencial do Lar Finance, tokens, dados financeiros, arquivos importados, backups, dispositivo e servidor doméstico. Ameaças prioritárias: vazamento do repositório/log, roubo de dispositivo, acesso externo indevido, perda/corrupção do disco, import malicioso, sessão não revogada e erro de sincronização.

## Estado dos achados da Sprint 1

### Mitigado externamente: credencial histórica

Os valores foram removidos dos scripts no HEAD e o CI ganhou secret scanning. Em
2026-08-12, o proprietário rotacionou a senha diretamente no console do EasyPanel,
sem registrar o novo valor. O Django confirmou senha utilizável com
`pbkdf2_sha256`; todas as sessões Django existentes foram removidas. A imagem em
produção ainda não contém o pacote da API móvel, portanto não havia sessões de
dispositivo dessa API para revogar.

Permanecem estas ações:

- manter scripts/fixtures somente com variáveis e dados sintéticos;
- nunca reutilizar a credencial antiga em outro serviço;
- avaliar remoção do histórico Git após backup e coordenação, pois reescrever histórico é destrutivo `[INVESTIGAR autorização]`.

Não reproduzir os valores em tickets, docs ou logs.

### Resolvido no código: volume SQLite

O Compose monta `/app/data` e usa `SQLITE_PATH=/app/data/db.sqlite3`, com uma
réplica e um worker. O mecanismo passou por ensaio sintético e, em 2026-08-12,
um backup real foi enviado a um bucket R2 privado e restaurado com hash, migrations,
auditoria e integridade aprovados. O repositório agora inclui um scheduler
supervisionado que cria o backup pela API do SQLite e o confirma no R2, sem depender
do job nativo incompatível com o volume Docker legado. No EasyPanel `v2.33.1`, a
automação criou uma chave idempotente, sobreviveu a restart e o objeto foi
restaurado no servidor e off-host em 2026-08-13. Rate limit, rollback por digest
OCI e alertas externos permanecem abertos. PostgreSQL continua a direção futura,
não uma mudança autorizada nesta sprint.

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

- o servidor atual usa SQLite com uma réplica e um worker; PostgreSQL protegido
  por rede interna e credencial exclusiva é a direção futura `[INVESTIGAR]`;
- volumes do servidor com permissão mínima;
- backups enviados ao R2 por TLS e protegidos pela criptografia gerenciada do R2
  em repouso; criptografia client-side antes do upload não foi implementada;
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
- hash antes do processamento;
- no cliente, o arquivo escolhido existe apenas em memória entre o seletor e o
  upload, o nome real nunca sai do adapter e o multipart usa o nome constante
  `statement.ofx`;
- os logs de importação carregam somente rota, status, request ID, duração e
  código de erro, sem identificador de dispositivo, descrição, valor ou hash.

## Backup 3-2-1 proporcional

- cópia primária no volume SQLite atual; adaptar a rotina quando a migração
  futura para PostgreSQL for autorizada `[INVESTIGAR]`;
- cópia temporária consistente criada em staging exclusivo sob
  `/app/data/backups` e normalmente removida; se o processo for encerrado sem
  unwind ou o `unlink` falhar, o temporário SQLite, seu sidecar ou o temporário R2
  pode permanecer. A tentativa seguinte faz uma limpeza automática restrita sob
  o mesmo file lock; se ela também falhar,
  siga o [procedimento seguro do runbook](sprints/automatic-r2-backup.md#resíduo-temporário-depois-de-falha);
  ela é apenas etapa do upload e não conta como segunda cópia persistente;
- cópia real fora do servidor/casa em bucket R2 privado, transferida por TLS, com
  criptografia gerenciada pelo provedor em repouso e restauração provada em
  2026-08-12;
- automação R2 codificada com 14 backups diários, 8 domingos semanais e 12
  primeiros dias mensais; objetos desconhecidos e o último backup válido são
  preservados;
- teste automatizado de integridade;
- restauração ensaiada periodicamente em ambiente isolado;
- RPO/RTO iniciais `[INVESTIGAR]` após entender tolerância do usuário.

Backup só é considerado válido após restauração testada. A prova de 2026-08-12
validou o mecanismo manual; em 2026-08-13, a automação também criou e confirmou
o objeto do dia e ele foi restaurado em cópias descartáveis no servidor e
off-host. Isso não substitui o ensaio do objeto que será selecionado para uma
nova release.

O token operacional R2 deve ter somente Object Read & Write, limitado ao bucket
privado de backup. Isso cobre listar, ler, criar e excluir objetos sem conceder
acesso a outros buckets. Access key e secret ficam apenas no secret store do
EasyPanel. O runbook reproduzível está em
`docs/sprints/automatic-r2-backup.md`.

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

O processo de backup emite um evento JSON sanitizado em stdout com horário,
serviço, evento, status, etapa, chave lógica, tamanho, prefixo do SHA-256, duração,
quantidade excluída e código de erro. Credenciais e conteúdo financeiro não são
campos do evento. Alertas externos para esses eventos continuam pendentes.

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

O contrato de release começa pela tag versionada/controlada
`ghcr.io/ludsonfrancisco/finanpy:sha-<sha Git de 40 caracteres>`; a identidade
imutável é o digest OCI que deve ser registrado na publicação. Sem sobrescrever
o command da imagem, o entrypoint executa preflight, backup opcional, `migrate`,
auditoria e `collectstatic`; somente então inicia o Supervisor. Falha em qualquer
etapa impede o web e os dois schedulers de iniciar.

Topologia suportada: uma réplica, um worker Gunicorn, um `backup-scheduler` e um
`import-preview-purge`. O health retorna exatamente `status`, `api_version` e
`version`, e a versão precisa coincidir com o SHA da imagem selecionada.

Checklist operacional sem segredos:

- domínio e certificado;
- tag versionada, digest OCI e associação tag→digest observada;
- variáveis e secret store;
- volumes e owners;
- volume SQLite atual; PostgreSQL e rede privada somente após a migração futura;
- healthcheck, SHA e restart;
- entrypoint da imagem preservado, sem migration manual paralela;
- rollback manual da imagem: parar processos, preservar o banco que falhou,
  verificar/restaurar uma cópia staged no mesmo filesystem e selecionar o digest
  anterior quando suportado;
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

Para o candidato R1.4, matriz local e CI estão comprovadas; publicação GHCR,
download/restauração R2 do objeto selecionado, imagem anterior e validação no
EasyPanel permanecem gates da Task 7. Veja
`docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md`.
