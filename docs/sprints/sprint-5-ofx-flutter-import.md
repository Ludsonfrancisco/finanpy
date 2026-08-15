# Sprint 5 — Importação OFX Nubank no Flutter

## Resultado

O cliente Flutter passa a importar um extrato OFX Nubank de conta ou cartão sem
recorrer ao web. O aparelho seleciona o arquivo pelo seletor nativo, envia por
multipart autenticado, lê uma prévia detalhada e paginada e só grava o ledger
depois de uma confirmação explícita. O servidor continua sendo a autoridade: o
Flutter não interpreta OFX, não deduplica e não cria transação local.

A importação segue **manual**. Nada de Open Finance, CSV, PDF, outros bancos,
limite de cartão, fatura ou parcelas nesta sprint.

## Entregue

### Backend

- parser compatível com as duas variantes estruturais reais do perfil Nubank,
  com fixtures sintéticas para cada uma;
- criação idempotente da conta padrão `Nubank — Conta` (`checking`) ou
  `Nubank — Cartão` (`credit`), moeda BRL, saldo inicial zero e responsável
  ativo `Eu`. Uma conta existente só é reaproveitada quando há exatamente um
  candidato idêntico; dois candidatos param a importação em vez de escolher;
- `ImportRecord.uuid` público, criado pela migration `0004_import_record_uuid`
  em três estágios, com backfill em lotes e triggers de fronteira recriados;
- prévia detalhada e paginada em `GET /api/v1/imports/{uuid}/?after=&limit=`,
  ordenada por `line_number, pk`, com `next_cursor` decimal, contagens e totais
  calculados em uma única agregação SQL;
- item da prévia exposto por UUID, com data civil, descrição, magnitude de duas
  casas, tipo e resultado. FITID, identificador da conta, fingerprint, hash do
  arquivo e `line_number` nunca saem no payload;
- código de erro estável `invalid_import_page` para cursor ou limite inválidos.

### Flutter

- `file_picker 12.0.0` com pin exato, usando apenas o seletor de documentos;
  nenhuma permissão ampla de armazenamento é solicitada;
- seleção que recusa extensão diferente de `.ofx` e arquivo acima de 10 MiB
  antes de ler os bytes. O nome real do arquivo morre dentro do adapter e o
  upload usa o nome constante `statement.ofx`;
- parser de domínio atômico: UUID canônico, data civil existente, instante
  RFC3339 em UTC, valores em minor units inteiros e enums conhecidos. Nenhum
  `double` no domínio financeiro;
- `ServerFailure` opcional no transporte, que carrega somente código e status;
  a mensagem remota nunca vira conteúdo de interface;
- controller serializado por época monotônica, com confirmação idempotente por
  future em voo, bytes descartados assim que o upload termina e resultados
  tardios ignorados após `dispose()`;
- tela adaptativa Casa de Valores: fluxo vertical no mobile com resumo antes da
  lista e ações persistentes num rodapé próprio; painel lateral de resumo e
  ações no Windows a partir de 900 px;
- acessibilidade verificada em 320 px com escala de 200%, alvos de 48 dp,
  navegação por `Tab`, `Enter` para confirmar, `Escape` para cancelar, foco
  devolvido ao erro e alternativa estática quando as animações estão desligadas.

## Evidência

| Gate | Resultado |
| --- | --- |
| Testes Django | 487 |
| Cobertura backend | acima do gate de 90% |
| Testes Flutter | 285 |
| Goldens de importação | 4 (mobile e Windows, claro e escuro) |
| Integração Windows | `integration_test/ofx_import_preview_test.dart` |
| Ruff, `check`, `makemigrations --check` | limpos |
| `dart format`, `flutter analyze` | limpos |

O teste de integração usa somente um servidor HTTP local e dados sintéticos. Ele
atravessa login, escolha de responsável, Home, seleção de arquivo, refresh único
de token durante o upload, prévia paginada, confirmação, pull do ledger e
cancelamento de uma segunda prévia. Ele também prova que `/sync/push/` nunca é
chamado e que o multipart carrega o nome constante.

## Correção descoberta pela integração

Reenviar um `FormData` após um 401 falhava: o corpo multipart é um fluxo que não
pode ser consumido duas vezes. O transporte passou a clonar o corpo a cada
tentativa, com teste dedicado. Sem essa correção, todo upload que encontrasse um
access token expirado quebraria em produção.

## Privacidade

- nenhum OFX real foi versionado; todas as fixtures são sintéticas e usam
  identificadores `synthetic-*`;
- o arquivo bruto existe apenas em memória durante seleção, upload e parse;
- os logs de importação carregam somente rota, status, request ID, duração e
  código de erro, sem `device_uuid`, descrição, valor ou hash;
- o diff da branch foi auditado contra caminhos de Downloads, nomes de arquivos
  reais, identificadores bancários, tokens e segredos.

## Candidato de release

Builds locais desta branch, com o endpoint público e sem credencial embutida:

- `flutter build apk --release`: `app-release.apk`, 57,9 MB;
- `flutter build windows --release`: `lar_finance.exe`;
- `dart run msix:create --install-certificate false`: `lar_finance.msix`,
  14.925.260 bytes, SHA-256
  `A8D6A13F831095802D0C661C7E2C76ABE4969D626F1D3B587BF08B79F94846EE`.

O MSIX continua assinado pelo certificado de teste embarcado da ferramenta, como
na Sprint 4: serve a um piloto controlado, nunca a distribuição. O sideload
segue o procedimento descrito na entrega da Sprint 4.

## Limites conhecidos

- a prévia de um arquivo já confirmado chega com `record_count` zero e
  `duplicate_count` preenchido, porque o backend não regrava as linhas de um
  arquivo repetido. A tela anuncia o estado e bloqueia a confirmação;
- limite de cartão, fatura, parcelas e conciliação de transferências continuam
  fora do escopo e pertencem à Sprint 6;
- o `flutter build windows` não roda de dentro de um worktree aninhado neste
  host por causa do limite de caminho do Windows; a prova foi feita a partir de
  um caminho curto e a CI usa o checkout raiz.

## Validação real pendente

Nada foi mesclado, implantado ou instalado por esta sprint, e nenhum arquivo
real foi importado. A validação com os extratos reais exige, em sequência e com
autorização separada para cada passo: merge em `main`, deploy com migrations
controladas no EasyPanel, instalação do app Windows, seleção do OFX de conta,
conferência da prévia antes de qualquer confirmação e, só então, a confirmação.
O mesmo gate se repete para o arquivo de cartão. Se a prévia divergir, o
caminho é cancelar — nunca corrigir dados direto no banco.
