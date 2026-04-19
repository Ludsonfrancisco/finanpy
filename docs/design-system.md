# Design System

Design moderno, clean e premium. Paleta principal baseada em **teal/emerald** para ações positivas, **slate** frio nos fundos e **amber** para destaques financeiros.

## Paleta de cores

| Token | Uso | Classe Tailwind |
|---|---|---|
| Primária | CTAs, links, destaques | `emerald-500`, `emerald-600` |
| Primária hover | Interação | `emerald-700` |
| Secundária | Destaques financeiros | `amber-400`, `amber-500` |
| Receitas | Valores positivos | `emerald-500` |
| Despesas | Valores negativos | `rose-500` |
| Fundo app | Background global | `slate-950` |
| Fundo card | Cards e painéis | `slate-900` |
| Fundo input | Inputs e selects | `slate-800` |
| Borda | Divisores e bordas | `slate-700` |
| Texto principal | Conteúdo | `slate-100` |
| Texto secundário | Legendas, placeholders | `slate-400` |
| Gradiente hero | Landing/banners | `from-emerald-500 via-teal-500 to-cyan-500` |

## Tipografia

- Fonte: **Inter** (Google Fonts)
- Títulos: `font-semibold tracking-tight`
- Corpo: `font-normal leading-relaxed`
- Escala: `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl`, `text-4xl`

## Layouts base

| Template | Uso |
|---|---|
| `base.html` | Base global com doctype, meta, CDN Tailwind e fonte Inter |
| `layouts/base_public.html` | Área pública: topbar simples + footer |
| `layouts/base_app.html` | Área autenticada: sidebar + topbar + conteúdo |

A área autenticada usa `max-w-7xl mx-auto p-6` na área de conteúdo.

## Componentes

### Botão primário

```html
<button class='inline-flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 px-5 py-2.5 text-sm font-semibold text-white shadow-lg shadow-emerald-500/20 transition hover:from-emerald-600 hover:to-teal-600 focus:outline-none focus:ring-2 focus:ring-emerald-400'>
  Salvar
</button>
```

### Botão secundário

```html
<button class='inline-flex items-center justify-center gap-2 rounded-xl border border-slate-700 bg-slate-800 px-5 py-2.5 text-sm font-semibold text-slate-100 transition hover:bg-slate-700'>
  Cancelar
</button>
```

### Input

```html
<input class='w-full rounded-xl border border-slate-700 bg-slate-800 px-4 py-2.5 text-slate-100 placeholder-slate-500 transition focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/40' />
```

### Label

```html
<label class='mb-1.5 block text-sm font-medium text-slate-300'>E-mail</label>
```

### Card

```html
<div class='rounded-2xl border border-slate-800 bg-slate-900/80 p-6 shadow-xl shadow-black/20 backdrop-blur'>
  ...
</div>
```

### Card de métrica (dashboard)

```html
<div class='rounded-2xl bg-gradient-to-br from-slate-800 to-slate-900 p-6 ring-1 ring-slate-700/50'>
  <p class='text-sm text-slate-400'>Saldo total</p>
  <p class='mt-2 text-3xl font-semibold text-emerald-400'>R$ 12.430,00</p>
</div>
```

### Tabela de listagem

```html
<div class='overflow-hidden rounded-2xl border border-slate-800'>
  <table class='w-full text-sm'>
    <thead class='bg-slate-800/60 text-slate-300'>
      <tr><th class='px-4 py-3 text-left font-medium'>...</th></tr>
    </thead>
    <tbody class='divide-y divide-slate-800 bg-slate-900'>
      <tr class='hover:bg-slate-800/50'><td class='px-4 py-3'>...</td></tr>
    </tbody>
  </table>
</div>
```

### Sidebar

```html
<aside class='w-64 border-r border-slate-800 bg-slate-950 p-4'>
  <nav class='flex flex-col gap-1'>
    <a class='flex items-center gap-3 rounded-xl px-3 py-2 text-slate-300 hover:bg-slate-800 hover:text-white' href='...'>Item</a>
    <a class='flex items-center gap-3 rounded-xl bg-emerald-500/10 px-3 py-2 text-emerald-400' href='...'>Ativo</a>
  </nav>
</aside>
```

### Topbar

```html
<header class='flex items-center justify-between border-b border-slate-800 bg-slate-950/80 px-6 py-4 backdrop-blur'>
  ...
</header>
```

### Mensagem de feedback

```html
<div class='rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-300'>
  Operação realizada com sucesso.
</div>
```

## Convenções de espaçamento e bordas

- Espaçamento: múltiplos de 4 (padrão Tailwind)
- Border radius padrão: `rounded-xl` (12px)
- Border radius em cards: `rounded-2xl` (16px)
- Sombras: `shadow-black/20`
