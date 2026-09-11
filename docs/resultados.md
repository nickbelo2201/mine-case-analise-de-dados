# Resultados das análises

> Gerado automaticamente por `scripts/rodar_tudo.mjs` sobre a **base sintética** (nenhum dado real do cliente). Valores em R$.

## Volume da base gerada

| t | n |
| --- | --- |
| products | 38 |
| product_variants | 304 |
| customers | 2.500 |
| orders | 4.381 |
| order_items | 6.332 |
| order_events | 16.812 |
| pos_sales | 2.433 |
| pos_sale_items | 3.480 |
| pos_payments | 2.754 |
| cash_sessions | 312 |
| stock_movements | 9.711 |

## 01_receita_mensal_por_canal

_como a receita evolui mês a mês, e quanto dela já vem do online?_ — [ver SQL](../sql/analytics/01_receita_mensal_por_canal.sql)

| mes | receita_rs | vendas | ticket_medio_rs | pct_online | var_mom_pct | media_movel_3m_rs |
| --- | --- | --- | --- | --- | --- | --- |
| 2025-09 | 132.201,53 | 366 | 361,21 | 62,4 | — | 132.201,53 |
| 2025-10 | 125.748,6 | 369 | 340,78 | 62,7 | -4,9 | 128.975,07 |
| 2025-11 | 215.542,16 | 607 | 355,09 | 62,8 | 71,4 | 157.830,76 |
| 2025-12 | 272.710,82 | 757 | 360,25 | 60,7 | 26,5 | 204.667,19 |
| 2026-01 | 119.395,06 | 336 | 355,34 | 57,7 | -56,2 | 202.549,35 |
| 2026-02 | 119.134,15 | 351 | 339,41 | 63,7 | -0,2 | 170.413,34 |
| 2026-03 | 148.455,36 | 431 | 344,44 | 62,2 | 24,6 | 128.994,86 |
| 2026-04 | 174.169,98 | 500 | 348,34 | 61,9 | 17,3 | 147.253,16 |
| 2026-05 | 269.131,91 | 784 | 343,28 | 67,1 | 54,5 | 197.252,42 |
| 2026-06 | 196.735,52 | 572 | 343,94 | 59,6 | -26,9 | 213.345,8 |
| 2026-07 | 205.135,22 | 594 | 345,35 | 61,6 | 4,3 | 223.667,55 |
| 2026-08 | 211.392,11 | 621 | 340,41 | 62,7 | 3,1 | 204.420,95 |

## 02_dre_por_canal

_qual canal dá mais dinheiro de verdade, depois de desconto, custo e taxa?_ — [ver SQL](../sql/analytics/02_dre_por_canal.sql)

| canal | vendas | receita_bruta_rs | descontos_rs | frete_rs | receita_liquida_rs | cmv_rs | taxas_rs | margem_contrib_rs | margem_pct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| site | 3.060 | 1.056.683,1 | 13.560,69 | 33.412,1 | 1.076.534,51 | 435.750,49 | 0 | 640.784,02 | 59,5 |
| loja | 2.394 | 839.451,6 | 13.235 | 0 | 826.216,6 | 346.510,88 | 16.493,13 | 463.212,59 | 56,1 |
| whatsapp | 834 | 282.609,3 | 4.801,79 | 9.193,8 | 287.001,31 | 116.237,22 | 0 | 170.764,09 | 59,5 |
| TOTAL | 6.288 | 2.178.744 | 31.597,48 | 42.605,9 | 2.189.752,42 | 898.498,59 | 16.493,13 | 1.274.760,7 | 58,2 |

## 03_rfm_segmentacao

_quem são as melhores clientes, e quem está sumindo?_ — [ver SQL](../sql/analytics/03_rfm_segmentacao.sql)

| segmento | clientes | recencia_media_dias | compras_media | valor_medio_rs | receita_rs | pct_receita |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Campeãs | 476 | 26 | 6 | 2.114,14 | 1.006.328,32 | 52,2 |
| 2. Leais | 433 | 65 | 2,8 | 960,21 | 415.772,38 | 21,6 |
| 3. Novas / promissoras | 148 | 31 | 1 | 338,14 | 50.045,33 | 2,6 |
| 4. Em risco (eram boas) | 128 | 174 | 2,9 | 1.177,64 | 150.737,81 | 7,8 |
| 5. Precisam de atenção | 264 | 146 | 1,5 | 468,57 | 123.703,04 | 6,4 |
| 6. Hibernando | 516 | 239 | 1 | 351,52 | 181.383,58 | 9,4 |

## 04_coorte_recompra

_das clientes que compraram pela primeira vez em cada mês, quantas voltaram 1, 2, 3 e 6 meses depois?_ — [ver SQL](../sql/analytics/04_coorte_recompra.sql)

| coorte | clientes_novas | m1_pct | m2_pct | m3_pct | m6_pct | voltou_ate_hoje_pct |
| --- | --- | --- | --- | --- | --- | --- |
| 2025-09 | 286 | 15,7 | 27,6 | 31,8 | 19,6 | 80,4 |
| 2025-10 | 247 | 22,7 | 27,1 | 16,6 | 18,6 | 76,5 |
| 2025-11 | 300 | 25,3 | 10,3 | 12 | 28,7 | 72,3 |
| 2025-12 | 283 | 9,9 | 15,9 | 12,4 | 21,2 | 63,6 |
| 2026-01 | 107 | 12,1 | 18,7 | 9,3 | 13,1 | 58,9 |
| 2026-02 | 92 | 12 | 12 | 15,2 | 16,3 | 54,3 |
| 2026-03 | 114 | 13,2 | 16,7 | 13,2 | — | 51,8 |
| 2026-04 | 126 | 17,5 | 16,7 | 19,8 | — | 49,2 |
| 2026-05 | 156 | 12,2 | 13,5 | 9,6 | — | 32,7 |
| 2026-06 | 85 | 12,9 | 12,9 | — | — | 23,5 |
| 2026-07 | 80 | 12,5 | — | — | — | 12,5 |
| 2026-08 | 89 | — | — | — | — | 0 |

## 05_curva_abc_produtos

_quais produtos sustentam a loja? (Pareto / curva ABC)_ — [ver SQL](../sql/analytics/05_curva_abc_produtos.sql)

| posicao | produto | categoria | pecas | receita_rs | margem_pct | pct_acumulado | classe |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Blusão Fleece Premium | moletons | 1.327 | 358.157,3 | 62 | 16,4 | A |
| 2 | Jaqueta Couro Eco Premium | jaquetas | 578 | 294.722,2 | 58 | 30 | A |
| 3 | Calça Jogger Premium | calcas | 218 | 76.278,2 | 57 | 33,5 | A |
| 4 | Jaqueta Jeans Premium | jaquetas | 221 | 75.117,9 | 59 | 36,9 | A |
| 5 | Moletom Careca Essencial | moletons | 289 | 75.111,1 | 58 | 40,4 | A |
| 6 | Moletom Careca Premium | moletons | 282 | 73.291,8 | 62 | 43,7 | A |
| 7 | Jaqueta Corta-vento Essencial | jaquetas | 316 | 69.488,4 | 54 | 46,9 | A |
| 8 | Calça Jogger Essencial | calcas | 274 | 68.472,6 | 60 | 50,1 | A |
| 9 | Jaqueta Corta-vento Premium | jaquetas | 145 | 65.235,5 | 59 | 53,1 | A |
| 10 | Bermuda Sarja Premium | bermudas | 328 | 55.727,2 | 61 | 55,6 | A |
| 11 | Jaqueta Couro Eco Essencial | jaquetas | 277 | 55.372,3 | 61 | 58,2 | A |
| 12 | Moletom Canguru Premium | moletons | 203 | 52.759,7 | 57 | 60,6 | A |
| 13 | Blusão Fleece Essencial | moletons | 197 | 51.200,3 | 53 | 62,9 | A |
| 14 | Calça Alfaiataria Premium | calcas | 196 | 50.940,4 | 61 | 65,3 | A |
| 15 | Bomber Essencial | jaquetas | 178 | 49.822,2 | 59 | 67,5 | A |
| 16 | Jaqueta Jeans Essencial | jaquetas | 198 | 49.480,2 | 57 | 69,8 | A |
| 17 | Camiseta Gola V Essencial | camisetas | 432 | 47.476,8 | 53 | 72 | A |
| 18 | Calça Jeans Reta Essencial | calcas | 199 | 45.750,1 | 54 | 74,1 | A |
| 19 | Bermuda Jeans Essencial | bermudas | 334 | 43.386,6 | 61 | 76,1 | A |
| 20 | Bomber Premium | jaquetas | 131 | 39.286,9 | 60 | 77,9 | A |
| 21 | Bermuda Jeans Premium | bermudas | 177 | 37.152,3 | 62 | 79,6 | A |
| 22 | Calça Jeans Reta Premium | calcas | 176 | 36.942,4 | 59 | 81,3 | B |
| 23 | Calça Cargo Premium | calcas | 180 | 35.982 | 59 | 82,9 | B |
| 24 | Bermuda Moletom Premium | bermudas | 205 | 34.829,5 | 55 | 84,5 | B |
| 25 | Camiseta Estampada Premium | camisetas | 221 | 33.127,9 | 54 | 86,1 | B |

_… mais 13 linhas._

## 06_giro_e_cobertura_estoque

_onde tem dinheiro parado no estoque e onde vai faltar peça?_ — [ver SQL](../sql/analytics/06_giro_e_cobertura_estoque.sql)

| situacao | variantes | pecas | capital_a_custo_rs | pct_capital | cobertura_media_dias |
| --- | --- | --- | --- | --- | --- |
| 1. Ruptura (vende e acabou) | 33 | 0 | 0 | 0 | 0 |
| 2. Repor em até 15 dias | 39 | 71 | 7.284,09 | 6,7 | 9 |
| 3. Saudável | 175 | 796 | 64.364,52 | 59,6 | 57 |
| 4. Excesso (> 120 dias) | 56 | 364 | 36.232,2 | 33,5 | 238 |
| 5. Parado (0 vendas em 90 dias) | 1 | 5 | 184,3 | 0,2 | — |

## 07_mix_pagamento_e_taxas

_quanto a maquininha come do faturamento do balcão?_ — [ver SQL](../sql/analytics/07_mix_pagamento_e_taxas.sql)

| forma | transacoes | valor_rs | pct_valor | parcelas_media | taxas_rs | taxa_efetiva_pct |
| --- | --- | --- | --- | --- | --- | --- |
| pix | 933 | 265.601,13 | 32,1 | — | 0 | 0 |
| credito | 853 | 243.603,18 | 29,5 | — | 7.796,31 | 3,2 |
| credito_parcelado | 431 | 144.201,9 | 17,5 | 4 | 7.067 | 4,9 |
| debito | 315 | 108.615,25 | 13,1 | — | 1.629,82 | 1,5 |
| dinheiro | 178 | 64.195,14 | 7,8 | — | 0 | 0 |

## 08_dia_da_semana_por_canal

_em que dia a loja e o online vendem? (escala de equipe e horário de campanha)_ — [ver SQL](../sql/analytics/08_dia_da_semana_por_canal.sql)

| dia_semana | dias_com_venda | media_vendas_loja | media_vendas_online | receita_media_dia_rs |
| --- | --- | --- | --- | --- |
| Seg | 53 | 7,6 | 10,5 | 6.410,11 |
| Ter | 52 | 7,6 | 9,4 | 5.938,19 |
| Qua | 52 | 7,5 | 9 | 5.838,4 |
| Qui | 52 | 7,6 | 10,3 | 6.222,94 |
| Sex | 52 | 7,1 | 9,3 | 5.744,68 |
| Sáb | 52 | 8,4 | 9,3 | 5.967,73 |
| Dom | 52 | 0 | 17 | 5.865,31 |

## 09_cancelamento_e_lead_time

_o online está perdendo pedidos? Quanto tempo a cliente espera pela peça?_ — [ver SQL](../sql/analytics/09_cancelamento_e_lead_time.sql)

| mes | pedidos | cancelado_pct | devolvido_pct | lead_time_mediano_dias | lead_time_p90_dias |
| --- | --- | --- | --- | --- | --- |
| 2025-09 | 260 | 7,7 | 3,5 | 6,5 | 8,6 |
| 2025-10 | 264 | 8,3 | 2,3 | 6,7 | 8,3 |
| 2025-11 | 417 | 7,4 | 1 | 6,3 | 8,5 |
| 2025-12 | 504 | 7,5 | 3,4 | 6,5 | 8,4 |
| 2026-01 | 213 | 5,6 | 5,6 | 6,6 | 8,6 |
| 2026-02 | 240 | 6,7 | 2,9 | 6,8 | 8,5 |
| 2026-03 | 300 | 5,3 | 3,7 | 6,4 | 8,5 |
| 2026-04 | 354 | 8,8 | 4,2 | 6,7 | 8,5 |
| 2026-05 | 569 | 6,9 | 2,8 | 6,5 | 8,4 |
| 2026-06 | 386 | 6,5 | 3,1 | 6,5 | 8,5 |
| 2026-07 | 414 | 6,3 | 3,9 | 6,3 | 8,5 |
| 2026-08 | 460 | 5,7 | 2,2 | 6,3 | 8,5 |

## 10_grade_de_tamanhos

_na hora de comprar do fornecedor, qual a proporção de cada tamanho por categoria?_ — [ver SQL](../sql/analytics/10_grade_de_tamanhos.sql)

| categoria | pecas | P_pct | M_pct | G_pct | GG_pct |
| --- | --- | --- | --- | --- | --- |
| moletons | 2.475 | 9,1 | 32,2 | 37,3 | 21,3 |
| camisetas | 2.395 | 20,8 | 36,1 | 23,9 | 19,2 |
| jaquetas | 2.044 | 8,3 | 30 | 40,2 | 21,4 |
| calcas | 1.600 | 20,4 | 37,2 | 25,3 | 17,1 |
| bermudas | 1.446 | 18,9 | 36,6 | 26,7 | 17,8 |

## 11_cesta_de_compras

_quais categorias saem juntas? (vitrine, combos, "compre junto")_ — [ver SQL](../sql/analytics/11_cesta_de_compras.sql)

| par | vendas_juntas | suporte_pct | confianca_a_para_b_pct | lift |
| --- | --- | --- | --- | --- |
| bermudas + camisetas | 558 | 8,87 | 43,7 | 1,31 |
| calcas + moletons | 448 | 7,12 | 31,9 | 0,93 |
| jaquetas + moletons | 471 | 7,49 | 26,8 | 0,78 |
| calcas + camisetas | 296 | 4,71 | 21,1 | 0,63 |
| camisetas + jaquetas | 188 | 2,99 | 9 | 0,32 |
| bermudas + jaquetas | 105 | 1,67 | 8,2 | 0,29 |
| camisetas + moletons | 187 | 2,97 | 8,9 | 0,26 |
| bermudas + moletons | 105 | 1,67 | 8,2 | 0,24 |
| calcas + jaquetas | 90 | 1,43 | 6,4 | 0,23 |
| bermudas + calcas | 63 | 1 | 4,9 | 0,22 |

## 12_qualidade_de_dados

_dá para confiar nesses números? Checagens que rodam antes de qualquer análise. Resultado esperado: tudo zero. A primeira usa a função de produção check_stock_integrity() (011_stock.sql): como o saldo é um ledger, a soma dos movimentos TEM que bater com o saldo._ — [ver SQL](../sql/analytics/12_qualidade_de_dados.sql)

| verificacao | ocorrencias |
| --- | --- |
| Saldo de estoque diverge da soma dos movimentos | 0 |
| Pedido com total ≠ itens − desconto + frete | 0 |
| Venda de balcão com pagamentos ≠ total | 0 |
| Cliente com WhatsApp fora do padrão E.164 (55 + DDD + número) | 0 |
| Item de pedido sem variante (estoque não rastreável) | 0 |
| Reserva maior que o saldo físico | 0 |
| Cliente criado depois da própria primeira compra | 0 |

## 13_funcoes_na_pratica

_Demonstração das funções de limpeza e padronização do schema. Dado de entrada sujo (como chega do formulário, da planilha antiga ou do WhatsApp) → dado canônico que o banco guarda._ — [ver SQL](../sql/analytics/13_funcoes_na_pratica.sql)

| entrada | funcao | saida |
| --- | --- | --- |
| (11) 98888-7777 | normalize_phone | 5511988887777 |
| 11988887777 | normalize_phone | 5511988887777 |
| +55 11 98888-7777 | normalize_phone | 5511988887777 |
| R$ 89,90 | parse_price_cents | 8990 |
| 1.299,00 | parse_price_cents | 129900 |
| 89.90 | parse_price_cents | 8990 |
| abc | parse_price_cents | NULL |
| Calça Alfaiataria Básica | slugify | calca-alfaiataria-basica |

