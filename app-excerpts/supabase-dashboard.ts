import { supabaseAdmin } from './supabase'
import { getLowStock } from './supabase-variants'

/**
 * Números da primeira tela do admin.
 *
 * Regra: todo número aqui tem uma ação associada. Nada é decorativo.
 */

export interface DashboardData {
  hoje: {
    totalCents: number
    vendas: number
    siteCents: number
    lojaCents: number
    /** Média diária dos 7 dias anteriores, para a comparação */
    mediaSeteDiasCents: number
  }
  atencao: {
    pedidosAguardando: number
    pedidosParados24h: number
    pecasAcabando: number
    foraDoSite: number
    reservasExpirando: number
  }
  mes: {
    faturamentoCents: number
    faturamentoAnteriorCents: number
    ticketMedioCents: number
    margemCents: number
    pecasVendidas: number
  }
  vendasPorDia: { dia: string; totalCents: number }[]
  topProdutos: { nome: string; quantidade: number; totalCents: number }[]
  estoqueParado: { nome: string; tamanho: string; cor: string; quantidade: number }[]
  valorEstoqueCents: number
  /** Datas já formatadas: ler o relógio durante o render é efeito colateral. */
  rotulos: { hoje: string; mes: string; corteEstoqueParado: string }
}

const DIA = 86_400_000

function inicioDoDia(offsetDias = 0): Date {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  d.setTime(d.getTime() - offsetDias * DIA)
  return d
}

const VENDIDO = ['confirmado', 'pago', 'enviado', 'entregue']

export async function getDashboard(): Promise<DashboardData> {
  const hoje = inicioDoDia()
  const seteDiasAtras = inicioDoDia(7)
  const trintaDiasAtras = inicioDoDia(30)
  const inicioMes = new Date(hoje.getFullYear(), hoje.getMonth(), 1)
  const inicioMesAnterior = new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1)

  const [pedidos, vendasLoja, lowStock, produtos, itensMes] = await Promise.all([
    supabaseAdmin
      .from('orders')
      .select('id, status, channel, total_cents, created_at, reserved_until')
      .gte('created_at', inicioMesAnterior.toISOString()),
    supabaseAdmin
      .from('pos_sales')
      .select('id, total_cents, cost_cents, created_at, status')
      .eq('status', 'concluida')
      .gte('created_at', inicioMesAnterior.toISOString()),
    getLowStock(),
    supabaseAdmin.from('products').select('id, name, status, price_cents, images'),
    supabaseAdmin
      .from('order_items')
      .select('quantity, unit_price_cents, cost_cents_snapshot, product_name_snapshot, order_id')
      .limit(5000),
  ])

  const orders = pedidos.data ?? []
  const posSales = vendasLoja.data ?? []

  const vendidos = orders.filter((o) => VENDIDO.includes(o.status))
  const pedidoPorId = new Map(orders.map((o) => [o.id, o]))

  // ---- Hoje ----
  const doDia = (iso: string) => new Date(iso) >= hoje
  const siteHoje = vendidos.filter((o) => doDia(o.created_at))
  const lojaHoje = posSales.filter((s) => doDia(s.created_at))

  const siteCents = siteHoje.reduce((s, o) => s + o.total_cents, 0)
  const lojaCents = lojaHoje.reduce((s, v) => s + v.total_cents, 0)

  const seteDias =
    vendidos
      .filter((o) => new Date(o.created_at) >= seteDiasAtras && new Date(o.created_at) < hoje)
      .reduce((s, o) => s + o.total_cents, 0) +
    posSales
      .filter((v) => new Date(v.created_at) >= seteDiasAtras && new Date(v.created_at) < hoje)
      .reduce((s, v) => s + v.total_cents, 0)

  // ---- Precisa da sua atenção ----
  const aguardando = orders.filter((o) => o.status === 'aguardando')
  const ontem = new Date(Date.now() - DIA)
  const agora = new Date()
  const em24h = new Date(Date.now() + DIA)

  // "Fora do site": cadastrada mas invisível para a cliente.
  const foraDoSite = (produtos.data ?? []).filter(
    (p) => p.status !== 'ativo' || !p.price_cents || !p.images?.length
  ).length

  // ---- O mês ----
  const noMes = (iso: string) => new Date(iso) >= inicioMes
  const noMesAnterior = (iso: string) =>
    new Date(iso) >= inicioMesAnterior && new Date(iso) < inicioMes

  const faturamentoMes =
    vendidos.filter((o) => noMes(o.created_at)).reduce((s, o) => s + o.total_cents, 0) +
    posSales.filter((v) => noMes(v.created_at)).reduce((s, v) => s + v.total_cents, 0)

  const faturamentoAnterior =
    vendidos.filter((o) => noMesAnterior(o.created_at)).reduce((s, o) => s + o.total_cents, 0) +
    posSales.filter((v) => noMesAnterior(v.created_at)).reduce((s, v) => s + v.total_cents, 0)

  const itensDoMes = (itensMes.data ?? []).filter((item) => {
    const order = pedidoPorId.get(item.order_id)
    return order && VENDIDO.includes(order.status) && noMes(order.created_at)
  })

  const pecasVendidas =
    itensDoMes.reduce((s, i) => s + i.quantity, 0) + posSales.filter((v) => noMes(v.created_at)).length

  // Margem usa o custo congelado no item — o custo da época da venda,
  // não o custo de hoje, senão a margem histórica muda sozinha.
  const custoMes =
    itensDoMes.reduce((s, i) => s + i.cost_cents_snapshot * i.quantity, 0) +
    posSales.filter((v) => noMes(v.created_at)).reduce((s, v) => s + v.cost_cents, 0)

  const numeroVendasMes =
    vendidos.filter((o) => noMes(o.created_at)).length +
    posSales.filter((v) => noMes(v.created_at)).length

  // ---- Movimento: 30 dias ----
  const porDia = new Map<string, number>()
  for (let i = 29; i >= 0; i--) {
    porDia.set(inicioDoDia(i).toISOString().slice(0, 10), 0)
  }
  const somaNoDia = (iso: string, cents: number) => {
    const key = new Date(iso).toISOString().slice(0, 10)
    if (porDia.has(key)) porDia.set(key, porDia.get(key)! + cents)
  }
  vendidos
    .filter((o) => new Date(o.created_at) >= trintaDiasAtras)
    .forEach((o) => somaNoDia(o.created_at, o.total_cents))
  posSales
    .filter((v) => new Date(v.created_at) >= trintaDiasAtras)
    .forEach((v) => somaNoDia(v.created_at, v.total_cents))

  // ---- Top produtos do mês ----
  const porProduto = new Map<string, { quantidade: number; totalCents: number }>()
  for (const item of itensDoMes) {
    const nome = item.product_name_snapshot ?? 'Sem nome'
    const atual = porProduto.get(nome) ?? { quantidade: 0, totalCents: 0 }
    atual.quantidade += item.quantity
    atual.totalCents += (item.unit_price_cents ?? 0) * item.quantity
    porProduto.set(nome, atual)
  }

  // ---- Estoque parado e valor imobilizado ----
  const { data: parado } = await supabaseAdmin
    .from('product_variants_available')
    .select('*')
    .gt('stock_on_hand', 0)

  const vendidasRecentemente = new Set(
    (
      await supabaseAdmin
        .from('stock_movements')
        .select('variant_id')
        .in('reason', ['venda_online', 'venda_loja'])
        .gte('created_at', inicioDoDia(60).toISOString())
    ).data?.map((m) => m.variant_id) ?? []
  )

  const valorEstoqueCents = (parado ?? []).reduce(
    (s, v) => s + v.stock_on_hand * (v.effective_price_cents ?? 0),
    0
  )

  return {
    hoje: {
      totalCents: siteCents + lojaCents,
      vendas: siteHoje.length + lojaHoje.length,
      siteCents,
      lojaCents,
      mediaSeteDiasCents: Math.round(seteDias / 7),
    },
    atencao: {
      pedidosAguardando: aguardando.length,
      pedidosParados24h: aguardando.filter((o) => new Date(o.created_at) < ontem).length,
      pecasAcabando: lowStock.length,
      foraDoSite,
      reservasExpirando: aguardando.filter(
        (o) =>
          o.reserved_until &&
          new Date(o.reserved_until) > agora &&
          new Date(o.reserved_until) < em24h
      ).length,
    },
    mes: {
      faturamentoCents: faturamentoMes,
      faturamentoAnteriorCents: faturamentoAnterior,
      ticketMedioCents: numeroVendasMes ? Math.round(faturamentoMes / numeroVendasMes) : 0,
      margemCents: faturamentoMes - custoMes,
      pecasVendidas,
    },
    vendasPorDia: [...porDia.entries()].map(([dia, totalCents]) => ({ dia, totalCents })),
    topProdutos: [...porProduto.entries()]
      .map(([nome, v]) => ({ nome, ...v }))
      .sort((a, b) => b.quantidade - a.quantidade)
      .slice(0, 10),
    estoqueParado: (parado ?? [])
      .filter((v) => !vendidasRecentemente.has(v.id))
      .sort((a, b) => b.stock_on_hand - a.stock_on_hand)
      .slice(0, 20)
      .map((v) => ({
        nome: v.product_name,
        tamanho: v.size,
        cor: v.color,
        quantidade: v.stock_on_hand,
      })),
    valorEstoqueCents,
    rotulos: {
      hoje: hoje.toLocaleDateString('pt-BR', {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
      }),
      mes: hoje.toLocaleDateString('pt-BR', { month: 'long' }),
      corteEstoqueParado: inicioDoDia(60).toLocaleDateString('pt-BR', {
        day: 'numeric',
        month: 'long',
      }),
    },
  }
}
