# 1. Contexto e problema

## O negócio

A **MINE** é uma loja de moda que vende em três canais ao mesmo tempo:

| Canal | Como a venda acontece |
|---|---|
| **Loja física** | Balcão, com caixa, vendedoras, maquininha e pagamento dividido |
| **Site** | Catálogo online com checkout; o pedido fecha no WhatsApp |
| **WhatsApp** | Atendimento direto, pedido lançado à mão no painel |

## O que existia antes

Quando o projeto começou, o "banco de dados" era um catálogo para o site e nada mais:

- **Preço guardado como texto** (`"R$ 89,90"`), impossível de somar, ordenar ou filtrar.
- **Estoque como um JSON dentro do produto** (`sizes: [{"size":"M","stock":3}]`), sem histórico. Se o número estava errado, não havia como saber por quê.
- **Cada cor era um produto separado.** A mesma camiseta em preto e em branco virava dois cadastros, e as vendas da peça ficavam fragmentadas.
- **A loja física não existia no sistema.** As vendas de balcão ficavam no caderno e na maquininha, e o online no WhatsApp. Não havia uma visão única do faturamento.
- **Uma cliente virava várias.** `(11) 98888-7777`, `11988887777` e `+55 11 98888-7777` eram três pessoas diferentes.

Resultado: a dona não conseguia responder perguntas básicas como *"quanto eu vendi este mês?"*, *"qual peça dá mais lucro?"*, *"quem são minhas melhores clientes?"* ou *"vou vender online uma peça que já saiu no balcão?"*

## O que eu construí

Redesenhei o banco de dados (PostgreSQL no Supabase) para ser a **fonte única de verdade da operação**, e a partir dele um painel de gestão. Em 17 migrations incrementais, sem nunca parar o site:

1. **Catálogo normalizado:** produto → variante (cor × tamanho) como unidade real de estoque, com preço em centavos.
2. **Estoque como livro-razão (ledger):** todo movimento é uma linha, o saldo é consequência, e existe reserva anti-oversell entre os canais.
3. **Pedidos online com ciclo de vida completo** e histórico de status (`order_events`).
4. **Clientes deduplicadas** por WhatsApp normalizado, com compras do site e do balcão na mesma ficha.
5. **PDV completo:** caixa, vendas, pagamento dividido, taxa da maquininha e custo congelado.
6. **Segurança:** RLS em todas as tabelas, funções `SECURITY DEFINER` com `search_path` fixo e permissões revogadas de papéis públicos.
7. **Camada analítica** (neste case): views que unificam os canais e 13 análises SQL.

## Meu papel

Fiz o projeto de ponta a ponta: levantamento com a cliente, modelagem, migrations, migração dos dados legados, funções em PL/pgSQL, integração com o app (Next.js + TypeScript) e as análises.

## Por que o repositório original não é público

O código de produção pertence a um projeto real e **o repositório é privado por preferência do cliente**. Este repositório é um case de estudo: traz o **schema real** (as migrations, com credenciais, identificadores do projeto e contatos removidos), trechos da camada de consulta do app e uma camada analítica nova. Todos os dados são gerados sinteticamente. Nenhum dado de cliente, venda ou produto real aparece aqui.
