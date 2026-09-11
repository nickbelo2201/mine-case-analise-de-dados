# 4. Análises e insights

> Os números abaixo vêm da **base sintética** e servem para mostrar o método: a pergunta, a query, a leitura e a ação recomendada. A tabela completa de cada análise está em [resultados.md](resultados.md).

## Como a camada analítica foi pensada

1. **Um grão, uma regra.** `vw_vendas` junta pedido online e venda de balcão. A definição de "vendido" (pedido confirmado, pago, enviado ou entregue; venda de balcão concluída) aparece uma única vez. Em nenhuma análise alguém redefine faturamento com um `WHERE` diferente.
2. **Data de corte = último dado, não `now()`.** As análises usam `max(created_at)` como referência, então o resultado é reprodutível, e a mesma query gera o mesmo número amanhã.
3. **Fuso horário explícito.** `date_trunc('month', …)` roda com `timezone = America/Sao_Paulo`. Em UTC, uma venda às 22h do dia 31 cairia no mês seguinte.
4. **Qualidade antes de análise.** A [análise 12](../sql/analytics/12_qualidade_de_dados.sql) roda checagens que precisam dar zero antes de qualquer número ir para a dona.

---

## 01 · Receita mensal e crescimento

**Leitura:** novembro (+71% MoM) e dezembro concentram a temporada. Janeiro cai 56%, uma queda sazonal e não um problema. Maio sobe 55% com o Dia das Mães. A média móvel de 3 meses suaviza os picos e mostra a tendência: de ~R$ 129 mil (out) para ~R$ 204–224 mil (jun–ago).
**Ação:** comparar cada mês com o mesmo mês do ano anterior (YoY) quando houver histórico, porque o MoM puro engana em negócio sazonal. Planejar a compra de estoque de novembro já em setembro.

## 02 · DRE por canal

**Leitura:** o site é o maior canal (49% da receita líquida). A loja tem a menor margem de contribuição (56,1% contra 59,5%) por causa da **taxa de maquininha**: R$ 16,5 mil no ano, que não aparece em "faturamento".
**Ação:** incentivar PIX no balcão (desconto pequeno ainda sai mais barato que 3–5% de taxa).

## 03 · RFM

**Leitura:** as **Campeãs** (24% das clientes identificadas) geram 52% da receita. O segmento **Em risco** (128 clientes, média de 2,9 compras, sem voltar há 174 dias) é o de maior retorno por esforço: já provaram que gostam da loja.
**Ação:** exportar o segmento "Em risco" para uma campanha de WhatsApp. A base de contato já existe, porque o cliente é identificado pelo WhatsApp.

## 04 · Coorte de recompra

**Leitura:** as coortes de set–nov/2025 voltaram a comprar em 72–80% dos casos até agosto; as de 2026 ficam abaixo, em parte porque tiveram menos tempo para voltar. A taxa de mês 1 fica entre 10% e 25%. As células de meses que ainda não aconteceram saem como `NULL` (—), e não como 0%, para não parecer queda.
**Ação:** acompanhar o **m1**: é a primeira oportunidade de fidelizar e a métrica que responde mais rápido a uma régua de pós-venda.

## 05 · Curva ABC

**Leitura:** 2 produtos (Blusão Fleece Premium e Jaqueta Couro Eco Premium) somam **30% da receita**. Uma ruptura nesses dois tem impacto desproporcional.
**Ação:** estoque de segurança maior e reposição prioritária para a classe A; revisar a classe C para liquidação ou saída de linha.

## 06 · Giro e cobertura de estoque

**Leitura:** 33,5% do capital a custo está em variantes com **mais de 120 dias de cobertura**, enquanto 33 variantes que vendem estão **zeradas**. É o retrato clássico de compra por feeling: sobra onde não gira, falta onde gira.
**Ação:** usar a cobertura (estoque ÷ venda média diária dos últimos 90 dias) como gatilho de compra, junto com a curva ABC.

## 07 · Mix de pagamento

**Leitura:** o crédito parcelado é 17,5% do valor, mas cobra a maior taxa efetiva (4,9%). O PIX, com taxa zero, já é a forma mais usada (32%).

## 08 · Dia da semana

**Leitura:** a loja não abre aos domingos, e o domingo tem **quase o dobro** de pedidos online (17 contra ~9–10). A cliente não deixa de comprar, só muda de canal.
**Ação:** concentrar os disparos de campanha e a reposição do site no fim de semana.

## 09 · Cancelamento e lead time

**Leitura:** a taxa de cancelamento do online fica entre 5% e 9%, e a de devolução entre 1% e 6%. O prazo mediano do pedido à entrega é de **~6,5 dias**, e o P90 de ~8,5. Reportar a mediana e o P90 em vez da média evita que alguns atrasos longos distorçam o indicador.

## 10 · Grade de tamanhos

**Leitura:** camisetas, calças e bermudas concentram em **M** (~36%). Moletons e jaquetas deslocam para **G/GG** (~58–62% somados).
**Ação:** comprar grade diferente por categoria, e não a mesma grade para tudo.

## 11 · Cesta de compras

**Leitura:** **bermuda + camiseta** é o único par com lift > 1 (1,31). Juntas, aparecem mais do que o acaso explicaria, e 44% das vendas com bermuda levam camiseta.
**Ação:** combo "bermuda + camiseta" na vitrine e no site; exibir camisetas na página de bermuda.

## 12 · Qualidade de dados

As 7 checagens retornam zero: o saldo de estoque bate com o ledger, o total do pedido bate com os itens, os pagamentos batem com o total da venda, os telefones estão normalizados, não há item sem variante nem reserva maior que o saldo.
