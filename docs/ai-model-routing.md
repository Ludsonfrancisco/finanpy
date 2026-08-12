# Roteamento de modelos e intensidade

Esta política orienta a escolha de modelo e intensidade de raciocínio durante a
composição e a execução de sprints e tarefas do Lar Finance.

Objetivo: equilibrar qualidade, confiabilidade, risco, velocidade e consumo de
recursos. Usar a menor capacidade que entregue a qualidade exigida sem aumentar
de forma relevante o risco de erro.

## Regras obrigatórias

- Nunca inventar modelo, versão, intensidade, capacidade, limite, preço ou
  consumo de tokens.
- Usar somente opções confirmadas no ambiente ativo, informadas pelo usuário ou
  comprovadas em documentação oficial atual.
- Quando algo não puder ser confirmado, registrar: **Não verificável no ambiente
  atual.**
- Não escolher capacidade máxima apenas porque a entrega é importante.
- Não economizar quando erro for difícil de detectar, tiver alto impacto ou
  contaminar várias tarefas posteriores.
- Ferramenta necessária e complexidade cognitiva são decisões separadas.
- Tokens reais só podem ser registrados quando fornecidos pela plataforma.
  Caso contrário: **Tokens reais: não disponíveis.**

## Inventário do ambiente

O inventário deve ser refeito no início de cada sprint. Disponibilidade muda por
sessão, conta, ferramenta e política do ambiente; este documento não transforma
um snapshot em garantia futura.

Snapshot confirmado no ambiente de orquestração em 2026-08-12:

- `gpt-5.6-terra`: `low`, `medium`, `high`, `xhigh`, `max`, `ultra`;
- `gpt-5.6-sol`: `low`, `medium`, `high`, `xhigh`, `max`, `ultra`.

Este inventário confirma opções de subagentes no ambiente atual. Preços, limites,
consumo real e disponibilidade futura: **Não verificável no ambiente atual.**

## Avaliação interna da tarefa

Antes do roteamento, avaliar silenciosamente:

1. complexidade lógica: 0 a 4;
2. ambiguidade: 0 a 3;
3. dependências: 0 a 3;
4. risco de erro: 0 a 3;
5. necessidade de síntese: 0 a 3;
6. necessidade de planejamento: 0 a 3;
7. criatividade sob restrições: 0 a 3;
8. precisão exigida: 0 a 3.

Pontuação ajuda a análise, mas não substitui julgamento. Justificativa precisa
citar características reais da tarefa, não apenas chamá-la de “complexa”.

## Níveis de roteamento

### Econômico

Usar menor opção confirmada para transformação mecânica, extração direta,
formatação, classificação simples, pequenas edições, listas e execução com
regras claras.

Baseline atual: `gpt-5.6-terra` com `low`.

### Moderado

Padrão para trabalho profissional com análise real: comparação, planejamento,
código moderado, interpretação de requisitos, revisão crítica, inconsistências e
síntese de várias informações.

Baseline atual: `gpt-5.6-terra` com `medium` ou `high`, conforme risco.

### Alto

Reservado para arquitetura complexa, debugging sem causa evidente, requisitos
conflitantes, decisões estratégicas, migrations críticas, segurança, lógica
complexa e validação final de entregas de alto impacto.

Baseline atual: `gpt-5.6-sol` com `high` ou `xhigh`.

### Acima de `xhigh`

`max` ou `ultra` exigem justificativa excepcional: opção confirmada, complexidade
fora do comum, risco concreto de insuficiência no nível anterior e ganho provável
que compense o consumo. Nunca usar apenas “para garantir”.

## Composição de uma sprint

Antes de iniciar, registrar no documento da sprint:

```markdown
## Plano de modelos — Sprint [nome]

**Inventário confirmado:** [modelos e intensidades disponíveis]
**Complexidade geral:** Baixa / Média / Alta / Muito alta
**Estratégia de consumo:** [resumo curto]
**Modelo/intensidade predominante:** [modelo + intensidade]
**Motivo:** [características concretas]

| Tarefa | Modelo | Intensidade | Consumo esperado | Ferramentas | Motivo |
|---|---|---|---|---|---|
| Task 01 | ... | ... | Baixo/Médio/Alto | ... | ... |
```

“Consumo esperado” é sempre qualitativo. Não estimar quantidade de tokens.

## Antes de cada tarefa

Registrar de forma curta:

```markdown
### Routing — Task [ID]

**Modelo:** [modelo confirmado]
**Intensidade:** [nível confirmado]
**Motivo:** [máximo duas frases]
**Consumo esperado:** Baixo / Médio / Alto
**Ferramentas necessárias:** [lista ou nenhuma]
```

Governança deve custar menos que a própria tarefa.

## Escalonamento e redução

Escalar quando surgirem contradições, falhas repetidas, dependências ocultas,
contexto cruzado grande, baixa confiança ou risco superior ao previsto.

```markdown
**Escalonamento recomendado**
Atual: [modelo/intensidade]
Novo: [modelo/intensidade]
Motivo: [evidência concreta]
```

Se tarefa prevista como difícil mostrar-se simples, registrar redução recomendada
para tarefas futuras semelhantes. Não reduzir a tarefa atual se troca comprometer
continuidade ou custar mais que concluir.

## Auditoria de cada tarefa

Ao concluir:

```markdown
### Auditoria — Task [ID]

**Usado:** [modelo + intensidade]
**Por que:** [motivo concreto]
**Resultado:** Suficiente / Acima do necessário / Insuficiente
**Poderia usar nível menor:** Sim / Não
**Justificativa:** [uma ou duas frases]
**Recomendação para tarefas semelhantes:** [modelo/intensidade]
**Escalonamentos:** [lista ou nenhum]
**Tokens reais:** [valor fornecido pela plataforma ou “não disponíveis”]
```

## Auditoria da sprint

Depois de todas as tarefas e da revisão final:

```markdown
# Auditoria de modelos — Sprint [nome]

**Complexidade real:** [nível]
**Estratégia usada:** [resumo]
**Econômico:** [quantidade de tarefas]
**Moderado:** [quantidade]
**Alto:** [quantidade]
**Outros níveis confirmados:** [quantidade]
**Escalonamentos:** [tarefas ou nenhum]
**Excesso de capacidade:** [tarefas ou nenhum]
**Capacidade insuficiente:** [tarefas ou nenhum]
**Qualidade:** 1–5
**Eficiência de recursos:** 1–5
**Adequação das escolhas:** 1–5
**Tokens reais:** [valor fornecido ou “não disponíveis”]

## Conclusão
[até cinco linhas com aprendizados para a próxima sprint]
```

## Aprendizado entre sprints

- Reusar nível que resolveu tarefas semelhantes com qualidade e sem
  escalonamento.
- Subir baseline quando tarefas semelhantes falharem repetidamente em nível
  menor.
- Não generalizar um caso isolado; registrar padrão observado e evidência.
- Manter nível superior para segurança, arquitetura, integridade financeira e
  decisões usadas por muitas tarefas quando erro for difícil de detectar.
- Manter histórico dentro dos relatórios de sprint, permitindo formar perfil
  real de complexidade do Lar Finance.

## Princípio de decisão

Pergunta obrigatória:

> Qual é a opção menos custosa que provavelmente entregará esta tarefa no nível
> de qualidade exigido sem aumentar de forma relevante o risco de erro?

Eficiência significa capacidade proporcional à dificuldade real.
