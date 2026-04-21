# Agente de Análise Financeira — Documentação Técnica

## Visão geral

O agente de análise financeira (`ai` app) processa os dados transacionais de cada usuário e gera insights personalizados em linguagem natural usando LangChain 1.0 + OpenAI. Os resultados são persistidos no model `AIAnalysis` e exibidos no dashboard.

---

## Pipeline completo

```
run_finance_analysis (command)
    │
    ▼
User.objects.filter(is_active=True)   ← itera todos usuários ativos
    │
    ▼ (para cada usuário)
AnalysisService.run_for_user(user)
    │
    ├─ Coleta via ORM ──────────────────────────────────────────────────┐
    │   • Account.objects.filter(user=user)                             │
    │     → lista com name, type, current_balance                       │
    │   • Transaction.objects.filter(user=user, date__gte=period_start) │
    │     → total_income (Sum onde type='income')                       │
    │     → total_expense (Sum onde type='expense')                     │
    │     → net = total_income - total_expense                          │
    │     → category_breakdown: {nome: valor} via annotate+Sum          │
    └───────────────────────────────────────────────────────────────────┘
    │
    ▼
FinanceInsightAgent.analyze(context: dict)
    │
    ├─ Monta ChatPromptTemplate com system prompt + human message
    │   system: "Você é um analista financeiro pessoal. Analise os dados
    │             abaixo e responda em pt-BR com: 1 parágrafo de resumo
    │             seguido de uma lista JSON de insights acionáveis."
    │   human:  str(context)
    │
    ├─ Executa LCEL chain: prompt | ChatOpenAI(model, temp) | parser
    │
    └─ Retorna AnalysisResult(summary: str, insights: list[str])
    │
    ▼
AIAnalysis.objects.create(
    user, analysis_text, insights,
    period_start, period_end,
    model_used, tokens_used
)
    │
    ▼
Dashboard: AIAnalysis.objects.filter(user=...).order_by('-created_at').first()
```

---

## Estrutura de arquivos e responsabilidades

| Arquivo | Responsabilidade |
|---|---|
| `ai/models.py` | Define `AIAnalysis`; nenhuma lógica de negócio |
| `ai/agents/finance_insight_agent.py` | Constrói e executa o chain LangChain; único ponto de contato com OpenAI |
| `ai/services/analysis_service.py` | Orquestra coleta de dados ORM + chamada ao agente + persistência |
| `ai/management/commands/run_finance_analysis.py` | Entry point CLI; itera usuários; trata erros por usuário isoladamente |
| `ai/admin.py` | Registra `AIAnalysis` para inspeção e depuração via Django admin |

---

## Model AIAnalysis

```
AIAnalysis
├── user          FK → User (on_delete=CASCADE, related_name='ai_analyses')
├── analysis_text TextField  — texto narrativo gerado pelo LLM
├── insights      JSONField  — list[str], bullets acionáveis
├── period_start  DateField  — início do período (D-30 da execução)
├── period_end    DateField  — data da execução
├── model_used    CharField  — ex: 'gpt-5-mini'
├── tokens_used   IntegerField (null=True, blank=True)
└── created_at    DateTimeField (auto_now_add=True)
```

Não possui `updated_at` — registros de análise são imutáveis após criação.

---

## Integração LangChain 1.0

### Padrão LCEL (obrigatório)

LangChain 1.0 deprecou `LLMChain`. O único padrão suportado é LCEL com pipe `|`:

```
chain = prompt | llm | output_parser
result = chain.invoke({"context": context_str})
```

### Dependências (requirements/base.txt)

```
langchain>=1.0.0
langchain-openai>=0.3.0
langchain-core>=0.3.0
openai>=1.0.0
```

### Variável de ambiente

```
OPENAI_API_KEY=sk-...
```

Lida em `finance_insight_agent.py` via `os.environ['OPENAI_API_KEY']`. Nunca hardcoded.

---

## Execução

### Todos os usuários ativos

```bash
python manage.py run_finance_analysis
```

### Usuário específico (por ID)

```bash
python manage.py run_finance_analysis --user-id 3
```

### Via Docker

```bash
docker compose exec web python manage.py run_finance_analysis
```

---

## Tratamento de erros

- Erros por usuário são capturados com `try/except Exception` e logados via `self.stderr.write(...)`.
- O loop continua para os demais usuários — falha em um não aborta o comando.
- `OPENAI_API_KEY` ausente levanta `KeyError` antes do loop → falha imediata com mensagem clara.

---

## Exibição no Dashboard

- `DashboardView.get_context_data` consulta `latest_analysis = AIAnalysis.objects.filter(user=...).order_by('-created_at').first()`.
- Se `latest_analysis` é `None`, o card exibe estado vazio: "Nenhuma análise gerada ainda. Execute `python manage.py run_finance_analysis`."
- Se existe, exibe: data da análise, parágrafo de resumo, lista de bullets dos `insights`.

---

## Evolução futura

| Feature | Como implementar |
|---|---|
| Execução automática periódica | Celery Beat ou cron job via `django-crontab` |
| Análise sob demanda via UI | View `AIAnalysisCreateView` que chama `AnalysisService` diretamente |
| Histórico de análises | Página `ai/history.html` listando `AIAnalysis.objects.filter(user=user)` |
| Análise por período customizado | Parâmetros `--start` e `--end` no command |
| Múltiplos modelos | Campo `model_used` já prevê variação; parametrizar via `settings.AI_MODEL` |
| Streaming de resposta | `ChatOpenAI(streaming=True)` + SSE via Django Channels |
