# 3. Decisões técnicas

Cada decisão abaixo segue o formato: **problema → decisão → por quê → onde está no código**.

---

### D1. Estoque é um livro-razão, não um número

**Problema:** o estoque era um número editável dentro de um JSON. Quando divergia do físico, não havia como saber o que tinha acontecido.

**Decisão:** toda entrada ou saída é uma linha imutável em `stock_movements` (`delta`, `reason`, `ref_type`, `ref_id`, `created_by`). O saldo em `product_variants.stock_on_hand` é materializado para leitura rápida, mas **só muda por uma função**, `apply_stock_movement`, que grava o movimento e o saldo na mesma transação.

**Por quê:** dá auditoria completa, deixa reconstruir o saldo em qualquer data e permite checar a integridade. A função `check_stock_integrity()` compara a soma dos movimentos com o saldo; qualquer diferença indica bug.

**Onde:** [`011_stock.sql`](../sql/schema/011_stock.sql)

---

### D2. Reserva atômica contra venda dupla (oversell)

**Problema:** a mesma peça está à venda no site e no balcão. Se a última unidade sai na loja enquanto uma cliente fecha o pedido online, a loja vende o que não tem.

**Decisão:** o pedido online **reserva** a peça (`stock_reserved`) com um `UPDATE` condicional:

```sql
UPDATE product_variants v
   SET stock_reserved = v.stock_reserved + p_qty
 WHERE v.id = p_variant_id
   AND v.stock_on_hand - v.stock_reserved - v_safety >= p_qty;
-- 0 linhas afetadas = não havia saldo. Nunca "lê, decide, grava".
```

Além disso, o site nunca vê as últimas N peças (`site_safety_stock`), que ficam como colchão para o balcão. Pedidos não confirmados expiram (`release_expired_reservations`, com `FOR UPDATE SKIP LOCKED` para rodar em paralelo sem travar).

**Por quê:** ler o saldo na aplicação e depois gravar abre uma condição de corrida. O `UPDATE ... WHERE saldo >= qtd` é atômico no Postgres.

**Onde:** [`011_stock.sql`](../sql/schema/011_stock.sql), [`012_orders.sql`](../sql/schema/012_orders.sql)

---

### D3. O item congela preço e custo da época

**Problema:** se a margem histórica é calculada com o custo de hoje, ela muda sozinha quando o fornecedor reajusta o preço.

**Decisão:** `order_items` e `pos_sale_items` guardam `unit_price_cents`, `cost_cents_snapshot` e o nome, tamanho e cor do produto **no momento da venda**.

**Por quê:** fato de venda é imutável. É o mesmo princípio de uma tabela fato num data warehouse e de uma dimensão do tipo 2: o histórico não pode ser reescrito por uma mudança de cadastro.

**Onde:** [`012_orders.sql`](../sql/schema/012_orders.sql), [`014_pdv_e_usuarios.sql`](../sql/schema/014_pdv_e_usuarios.sql)

---

### D4. Uma cliente, um registro: WhatsApp normalizado como chave

**Problema:** o mesmo número chegava em vários formatos, e cada formato virava uma "cliente" nova. Isso fragmentava o histórico e subestimava recompra e LTV.

**Decisão:** `normalize_phone()` converte qualquer entrada para E.164 (só dígitos, com DDI 55), com `UNIQUE` na coluna. `upsert_customer()` usa `INSERT ... ON CONFLICT (whatsapp) DO UPDATE` e só troca o nome se o atual for um placeholder.

**Por quê:** a qualidade da chave define a qualidade de toda análise de cliente (RFM, coorte, LTV). Em varejo no Brasil, o WhatsApp é o identificador que a cliente de fato informa.

**Onde:** [`013_customers.sql`](../sql/schema/013_customers.sql)

---

### D5. Migração sem janela de manutenção (expand → migrate → contract)

**Problema:** o site estava no ar lendo o modelo antigo (`price` em texto, `sizes` em JSON).

**Decisão:**
1. **Expandir:** criar as colunas e tabelas novas sem remover nada (`009`).
2. **Migrar:** preencher o novo a partir do antigo com SQL idempotente (`010`). Nesse passo, `parse_price_cents("R$ 1.299,00") → 129900`, `jsonb_array_elements` explode `sizes` em linhas de variante, `unnest ... WITH ORDINALITY` preserva a ordem das fotos e `row_number()` desempata slugs repetidos.
3. **Sincronizar ao contrário:** um trigger (`sync_product_sizes`) mantém o JSON antigo atualizado a partir das variantes enquanto o site ainda o lê.
4. **Contrair** só depois de o app inteiro migrar.

A fusão de produtos que eram "a mesma peça em outra cor" **não foi automática**. A view `color_merge_candidates` lista os candidatos para revisão humana.

**Onde:** [`009_variants.sql`](../sql/schema/009_variants.sql), [`010_backfill_variantes.sql`](../sql/schema/010_backfill_variantes.sql)

---

### D6. "Vendi" ≠ "recebi"

**Problema:** o faturamento do balcão parecia 3 a 5% maior do que o dinheiro que de fato entrava.

**Decisão:** `pos_payments` registra uma linha por forma de pagamento (uma venda pode ser metade PIX, metade cartão) com `fee_cents` (a taxa da maquininha). O financeiro mostra os dois números com nomes diferentes.

**Onde:** [`014_pdv_e_usuarios.sql`](../sql/schema/014_pdv_e_usuarios.sql), [`app-excerpts/supabase-financeiro.ts`](../app-excerpts/supabase-financeiro.ts), [análise 07](../sql/analytics/07_mix_pagamento_e_taxas.sql)

---

### D7. Segurança no banco, não só na aplicação

- **RLS habilitado em todas as tabelas.** Catálogo e conteúdo têm leitura pública; todo o resto só é acessível pela service role.
- **Views ignoram RLS** (rodam com os direitos do dono), por isso a view que expõe custo teve o acesso **revogado** explicitamente dos papéis públicos.
- **O linter de segurança encontrou** que as funções `SECURITY DEFINER` estavam executáveis via API pela chave pública, o que permitiria trocar a senha do admin ou zerar o estoque. Corrigi na `016` com `REVOKE EXECUTE` e `search_path` fixo contra sequestro de schema.
- **Senhas** com bcrypt (`crypt` + `gen_salt('bf')`) no próprio Postgres.
- **LGPD:** a cliente é **anonimizada** (`anonymized_at`), nunca apagada, para não quebrar o histórico de vendas.

**Onde:** [`016_hardening_funcoes.sql`](../sql/schema/016_hardening_funcoes.sql), [`009_variants.sql`](../sql/schema/009_variants.sql), [`014_pdv_e_usuarios.sql`](../sql/schema/014_pdv_e_usuarios.sql)

---

### D8. Auditoria em JSONB

`audit_log` guarda quem, o quê, quando e o estado `before`/`after` em JSONB. Uma tabela única serve para qualquer entidade (preço, estoque, desconto, cancelamento) sem uma tabela de histórico por tabela.

**Onde:** [`014_pdv_e_usuarios.sql`](../sql/schema/014_pdv_e_usuarios.sql)
