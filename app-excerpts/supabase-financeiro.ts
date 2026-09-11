import { supabaseAdmin } from './supabase'
import type { PaymentMethod } from '@/types/database'

/**
 * Números do financeiro.
 *
 * Dois valores diferentes, com nomes diferentes de propósito:
 *  - "Vendi": regime de competência — a venda feita no período.
 *  - "Recebo de verdade": já sem a taxa da maquininha.
 * Tratar os dois como a mesma coisa é o jeito mais rápido de a dona
 * planejar com dinheiro que não existe.
 *
 * O custo usado é o congelado no item da venda (o custo da época), não o
 * custo de hoje — senão a margem histórica muda sozinha quando o
 * fornecedor reajusta.
 */

export type Periodo = 'hoje' | 'mes' | 'ano'

export interface Financeiro {
  faturamentoCents: number
  faturamentoOnlineCents: number
  faturamentoLojaCents: number
  custoCents: number
  taxasCents: number
  vendas: number
  porFormaPagamento: { method: PaymentMethod; totalCents: number }[]
}

const VENDIDO = ['confirmado', 'pago', 'enviado', 'entregue']

export function inicioDoPeriodo(periodo: Periodo): Date {
  const agora = new Date()
  if (periodo === 'hoje') {
    return new Date(agora.getFullYear(), agora.getMonth(), agora.getDate())
  }
  if (periodo === 'ano') return new Date(agora.getFullYear(), 0, 1)
  return new Date(agora.getFullYear(), agora.getMonth(), 1)
}

export async function getFinanceiro(periodo: Periodo): Promise<Financeiro> {
  const inicio = inicioDoPeriodo(periodo).toISOString()

  const [pedidos, vendasLoja] = await Promise.all([
    supabaseAdmin
      .from('orders')
      .select('id, status, total_cents, created_at')
      .gte('created_at', inicio),
    supabaseAdmin
      .from('pos_sales')
      .select('id, total_cents, cost_cents, created_at, status')
      .eq('status', 'concluida')
      .gte('created_at', inicio),
  ])

  // Sem este check a tela mostraria R$ 0,00 quando o banco falhou —
  // um zero silencioso é pior que uma mensagem de erro.
  if (pedidos.error) throw new Error(pedidos.error.message)
  if (vendasLoja.error) throw new Error(vendasLoja.error.message)

  const online = (pedidos.data ?? []).filter((p) => VENDIDO.includes(p.status))
  const loja = vendasLoja.data ?? []

  const idsOnline = online.map((o) => o.id)
  const idsLoja = loja.map((v) => v.id)

  const [itensOnline, pagamentos] = await Promise.all([
    idsOnline.length
      ? supabaseAdmin
          .from('order_items')
          .select('quantity, cost_cents_snapshot, order_id')
          .in('order_id', idsOnline)
      : Promise.resolve({ data: [], error: null }),
    idsLoja.length
      ? supabaseAdmin
          .from('pos_payments')
          .select('method, amount_cents, fee_cents')
          .in('sale_id', idsLoja)
      : Promise.resolve({ data: [], error: null }),
  ])

  if (itensOnline.error) throw new Error(itensOnline.error.message)
  if (pagamentos.error) throw new Error(pagamentos.error.message)

  const porForma = new Map<PaymentMethod, number>()
  for (const p of pagamentos.data ?? []) {
    porForma.set(p.method, (porForma.get(p.method) ?? 0) + p.amount_cents)
  }

  const faturamentoOnlineCents = online.reduce((s, o) => s + o.total_cents, 0)
  const faturamentoLojaCents = loja.reduce((s, v) => s + v.total_cents, 0)

  return {
    faturamentoOnlineCents,
    faturamentoLojaCents,
    faturamentoCents: faturamentoOnlineCents + faturamentoLojaCents,
    custoCents:
      (itensOnline.data ?? []).reduce(
        (s, i) => s + i.cost_cents_snapshot * i.quantity,
        0
      ) + loja.reduce((s, v) => s + v.cost_cents, 0),
    taxasCents: (pagamentos.data ?? []).reduce((s, p) => s + p.fee_cents, 0),
    vendas: online.length + loja.length,
    porFormaPagamento: [...porForma.entries()]
      .map(([method, totalCents]) => ({ method, totalCents }))
      .sort((a, b) => b.totalCents - a.totalCents),
  }
}
