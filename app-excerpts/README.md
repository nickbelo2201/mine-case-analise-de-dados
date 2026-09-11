# Trechos do app (TypeScript)

Dois arquivos reais da camada de dados do painel de gestão (Next.js + Supabase), incluídos para mostrar como as regras de negócio do banco chegam à tela. Eles não rodam sozinhos aqui, porque dependem do resto do app, que é privado.

| Arquivo | O que faz |
|---|---|
| [`supabase-dashboard.ts`](supabase-dashboard.ts) | Primeira tela do admin: vendas de hoje × média de 7 dias, faturamento e margem do mês, ticket médio, top produtos, estoque parado há 60 dias, pedidos que precisam de atenção |
| [`supabase-financeiro.ts`](supabase-financeiro.ts) | Financeiro: separa "vendi" (competência) de "recebo de verdade" (sem a taxa da maquininha), com custo congelado no item |

Regras que se repetem nos dois e na camada SQL ([`vw_vendas`](../sql/analytics/00_views_analiticas.sql)):

- `VENDIDO = ['confirmado', 'pago', 'enviado', 'entregue']`, a mesma definição de venda em todo lugar;
- margem calculada com `cost_cents_snapshot` (o custo da época), não com o custo atual;
- erro de consulta vira erro na tela, e nunca um `R$ 0,00` silencioso.

**Evolução:** hoje parte da agregação é feita em TypeScript. As views e queries deste case mostram o próximo passo: levar essas agregações para o banco (views ou funções), o que reduz o tráfego e deixa a regra num lugar só.
