# Importação e sincronização

## Estratégia aprovada

O Lar Finance começa com exportação/importação manual porque é a alternativa de menor custo e menor dependência. Quando a experiência estiver confiável, um provedor automático poderá ser conectado sem substituir o ledger, os importadores ou a conciliação.

## O que cada fonte pode trazer

| Fonte | Movimentações | Saldo | Cartão/fatura | Limite | Empréstimo | Investimentos | Observação |
|---|---:|---:|---:|---:|---:|---:|---|
| OFX | comum | às vezes | varia | raro | raro | raro | melhor para extrato; cobertura por banco `[INVESTIGAR]` |
| CSV | comum | varia | varia | raro | raro | raro | cabeçalhos e sinais mudam por instituição |
| PDF | comum | comum | comum | às vezes | às vezes | às vezes | layout visual muda; parser específico |
| XLS/XLSX | varia | varia | varia | varia | varia | varia | útil quando o banco fornece planilha |
| Cadastro manual | sim | sim | sim | sim | sim | sim | exige data de referência e origem manual |
| Provedor futuro | provável | provável | provável | varia | varia | varia | validar por instituição/produto/CPF |

“Importar tudo” significa aproveitar todo campo realmente presente e representar claramente o que não veio. Não significa inventar limite, CET, saldo ou posição.

## Instituições iniciais

- Nubank: titular e esposa.
- Banco Inter: titular e esposa.
- Santander: titular e esposa.
- Mercado Pago: titular.

Existem sete combinações pessoa+instituição informadas. O número real de contas, cartões e produtos por instituição será inventariado com arquivos anonimizados `[INVESTIGAR]`.

## Fluxo de importação

```mermaid
flowchart LR
    A["Escolher arquivo"] --> B["Hash e detecção"]
    B --> C["Selecionar proprietário/conta"]
    C --> D["Parse sem persistir no ledger"]
    D --> E["Normalizar e validar"]
    E --> F["Deduplicar e conciliar"]
    F --> G["Prévia com erros/avisos"]
    G -->|"Confirmar"| H["Commit atômico"]
    G -->|"Cancelar"| I["Descartar lote"]
    H --> J["Recibo e auditoria"]
```

### Estados do lote

`uploaded`, `detected`, `parsed`, `needs_mapping`, `preview_ready`, `committing`, `completed`, `completed_with_warnings`, `failed`, `cancelled`.

### Regras de deduplicação

Ordem de confiança:

1. identificador externo estável da fonte;
2. hash do arquivo + número/posição do registro;
3. fingerprint composto por conta, data, valor, descrição normalizada e documento;
4. similaridade com janela temporal, sempre como sugestão, nunca exclusão silenciosa.

Reimportar o mesmo arquivo deve resultar em zero novos lançamentos e um recibo explicando os ignorados.

### Conciliação

- transferência: saída de uma conta + entrada em outra;
- fatura: pagamento em conta + fatura/cartão;
- estorno: lançamento original + reversão;
- parcela: compra raiz + parcelas/faturas;
- saldo: snapshot informado + saldo calculado;
- duplicata provável: registros parecidos com decisão humana.

## Perfis de importador

Os adaptadores devem ser versionados por instituição e produto, por exemplo `nubank_card_csv_v1`. Mudança de layout cria nova versão e fixtures. Nunca alterar um parser antigo de forma que lotes passados deixem de ser reproduzíveis.

Fixture de teste:

- arquivo mínimo válido anonimizado;
- acentos e descrições longas;
- entrada, saída, tarifa, estorno, transferência e parcela;
- registro duplicado;
- data inválida/coluna ausente;
- valores com vírgula/ponto e sinais diferentes;
- arquivo grande para performance.

## Política de arquivos

Decisão pendente `[INVESTIGAR]`:

- **reter criptografado:** melhor auditoria/reprocessamento, maior risco e armazenamento;
- **reter só hash + normalizado:** menor exposição, pior reprodução;
- **retenção curta:** compromisso recomendado para piloto, com prazo a definir.

Pré-requisitos: limite de tamanho, MIME real, antivírus/validação, nome aleatório, acesso privado e exclusão segura.

## Sincronização de dispositivos

O mesmo login familiar pode manter sessões independentes no Windows, iPhone e Android. Cada dispositivo é revogável e guarda seu próprio responsável padrão. Uma importação poderá ser iniciada em qualquer plataforma; depois da revisão e confirmação no servidor, o resultado será sincronizado automaticamente para as demais.

```mermaid
sequenceDiagram
    participant App as Flutter
    participant Local as SQLite/outbox
    participant API as Django API
    participant DB as PostgreSQL
    App->>Local: grava alteração + operação
    App->>API: envia operação idempotente
    API->>DB: valida versão e aplica
    DB-->>API: nova versão/cursor
    API-->>App: confirmação ou conflito
    App->>API: busca delta após cursor
    API-->>App: mudanças e tombstones
    App->>Local: transação local atômica
```

Gatilhos: login, abertura do app, pull-to-refresh, retorno da rede, depois de alteração e background quando o sistema operacional permitir. A interface sempre mostra “Atualizado há...” e oferece sincronização manual.

## Conflitos

- categoria/nota: possível last-write-wins apenas se auditável `[INVESTIGAR]`;
- valor, conta, proprietário, fatura, dívida e exclusão: revisão obrigatória quando versões divergem;
- importação versus edição manual: preservar valor original e valor ajustado;
- duas fontes para o mesmo evento: conciliar, não duplicar.

## Adaptador futuro de provedor

Contrato interno:

- autorizar/revogar conexão;
- listar instituições e capacidades;
- sincronizar contas, saldos e transações por cursor;
- receber webhook idempotente;
- mapear estado/erro sem vazar payload sensível;
- apagar tokens ao revogar;
- registrar cobertura por campo.

Pierre é apenas o primeiro candidato. Antes de contratar: confirmar dois CPFs, sete conexões, Nubank/Inter/Santander/Mercado Pago, cartões/faturas/limites, histórico, frequência, API, webhooks, LGPD, exportação e preço total.

## Critérios de aceite

- arquivo inválido não altera o ledger;
- lote confirmado é atômico;
- reimportação é idempotente;
- toda linha tem resultado rastreável;
- erros mostram como corrigir sem expor dados em logs;
- nenhum campo ausente vira zero;
- conflito entre dispositivos nunca é descartado silenciosamente.
