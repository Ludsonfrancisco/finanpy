# Segurança, privacidade e operação

## Modelo de ameaça resumido

Ativos: credencial do Lar Finance, tokens, dados financeiros, arquivos importados, backups, dispositivo e servidor doméstico. Ameaças prioritárias: vazamento do repositório/log, roubo de dispositivo, acesso externo indevido, perda/corrupção do disco, import malicioso, sessão não revogada e erro de sincronização.

## Achados imediatos

### Crítico: segredo e PII versionados

`create_accounts.py` e `qa_create_accounts.py` contêm credencial/identificador em texto claro. Ações:

- rotacionar a credencial;
- substituir scripts por fixtures/factories e variáveis de ambiente;
- impedir nova ocorrência com secret scanning;
- avaliar remoção do histórico Git após backup e coordenação, pois reescrever histórico é destrutivo `[INVESTIGAR autorização]`.

Não reproduzir os valores em tickets, docs ou logs.

### Crítico: volume SQLite

O Compose monta um volume nomeado em `/app/db.sqlite3`, um caminho de arquivo. Volumes Docker são diretórios e essa configuração pode impedir boot ou persistir de forma inesperada. Correção mínima: montar diretório de dados e apontar o banco para ele. Direção final: PostgreSQL.

## Controles de autenticação

- signup público desativado;
- usuário criado administrativamente;
- senha forte com validadores Django;
- access token curto e refresh rotativo/revogável `[INVESTIGAR pacote]`;
- lista de dispositivos e ação “sair de todos”;
- rate limiting por conta/IP sem bloquear permanentemente o dono;
- biometria protege acesso local, não substitui autenticação do servidor;
- tokens em Keychain, Android Keystore e Windows Credential Locker;
- nenhum token em SQLite, crash report ou clipboard permanente.

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

JSON com timestamp, nível, serviço, ambiente, request/job ID, rota normalizada, status, duração e código de erro. Proibido: email completo, CPF, saldo, valor, descrição, token, arquivo e payload de provedor.

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
