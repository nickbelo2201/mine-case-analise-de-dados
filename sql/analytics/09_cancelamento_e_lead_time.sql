-- Pergunta: o online está perdendo pedidos? Quanto tempo a cliente espera pela peça?
-- Técnicas: pivot de eventos (order_events) com MIN() FILTER, mediana com
-- percentile_cont — média de prazo esconde os atrasos longos.
WITH eventos AS (
  SELECT order_id,
         MIN(created_at) FILTER (WHERE to_status = 'aguardando') AS criado_em,
         MIN(created_at) FILTER (WHERE to_status = 'entregue')   AS entregue_em
    FROM order_events
   GROUP BY order_id
)
SELECT TO_CHAR(DATE_TRUNC('month', o.created_at), 'YYYY-MM')                      AS mes,
       COUNT(*)                                                                   AS pedidos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.status = 'cancelado') / COUNT(*), 1) AS cancelado_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.status = 'devolvido') / COUNT(*), 1) AS devolvido_pct,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (
                ORDER BY EXTRACT(EPOCH FROM e.entregue_em - e.criado_em) / 86400))::NUMERIC, 1)
                                                                                  AS lead_time_mediano_dias,
       ROUND((PERCENTILE_CONT(0.9) WITHIN GROUP (
                ORDER BY EXTRACT(EPOCH FROM e.entregue_em - e.criado_em) / 86400))::NUMERIC, 1)
                                                                                  AS lead_time_p90_dias
  FROM orders o
  LEFT JOIN eventos e ON e.order_id = o.id
 WHERE o.channel IN ('site', 'whatsapp')
 GROUP BY 1
 ORDER BY 1;
