// Sobe um Postgres em memória (PGlite, Postgres 17 compilado para WebAssembly),
// aplica as migrations de produção, gera a base sintética e roda todas as
// análises. Os resultados vão para docs/resultados.md.
//
//   npm install
//   npm run tudo
//
// Não precisa de Docker nem de Postgres instalado.
import { PGlite } from '@electric-sql/pglite'
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto'
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..')
const ler = (...p) => readFileSync(join(raiz, ...p), 'utf8')
const sqls = (pasta) => readdirSync(join(raiz, pasta)).filter((f) => f.endsWith('.sql')).sort()

const db = new PGlite({ extensions: { pgcrypto } })
await db.exec(`set timezone = 'America/Sao_Paulo'`)

const t0 = Date.now()
await db.exec(ler('sql/local/00_supabase_shim.sql'))
const executar = async (pasta, f) => {
  try {
    return await db.exec(ler(pasta, f))
  } catch (e) {
    console.error(`\nFALHOU em ${pasta}/${f}: ${e.message}`)
    process.exit(1)
  }
}
for (const f of sqls('sql/schema')) {
  await executar('sql/schema', f)
  console.log('migration ok  ', f)
}
await executar('sql/seed', 'seed_sintetico.sql')
console.log('seed ok')

const contagem = await db.query(`
  select 'products' t, count(*) n from products union all
  select 'product_variants', count(*) from product_variants union all
  select 'customers', count(*) from customers union all
  select 'orders', count(*) from orders union all
  select 'order_items', count(*) from order_items union all
  select 'order_events', count(*) from order_events union all
  select 'pos_sales', count(*) from pos_sales union all
  select 'pos_sale_items', count(*) from pos_sale_items union all
  select 'pos_payments', count(*) from pos_payments union all
  select 'cash_sessions', count(*) from cash_sessions union all
  select 'stock_movements', count(*) from stock_movements`)

// Só formata como número o que o Postgres tipou como número (int, numeric, float).
// Texto que parece número — telefone, preço digitado — fica como veio.
const NUMERICOS = new Set([20, 21, 23, 700, 701, 1700])
const fmt = (v, numerico) => {
  if (v === null || v === undefined) return '—'
  if (v instanceof Date) return v.toISOString().slice(0, 10)
  if (numerico) return Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 2 })
  return String(v).replace(/\|/g, '\\|')
}
const tabela = ({ rows, fields }, limite = 25) => {
  if (!rows.length) return '_sem linhas_\n'
  const cols = fields.map((f) => f.name)
  const num = Object.fromEntries(fields.map((f) => [f.name, NUMERICOS.has(f.dataTypeID)]))
  const linhas = rows.slice(0, limite).map((r) => `| ${cols.map((c) => fmt(r[c], num[c])).join(' | ')} |`)
  const extra = rows.length > limite ? `\n_… mais ${rows.length - limite} linhas._\n` : ''
  return `| ${cols.join(' | ')} |\n| ${cols.map(() => '---').join(' | ')} |\n${linhas.join('\n')}\n${extra}`
}

let md = `# Resultados das análises\n\n` +
  `> Gerado automaticamente por \`scripts/rodar_tudo.mjs\` sobre a **base sintética** ` +
  `(nenhum dado real do cliente). Valores em R$.\n\n` +
  `## Volume da base gerada\n\n${tabela(contagem)}\n`

for (const f of sqls('sql/analytics')) {
  const sql = ler('sql/analytics', f)
  const res = await executar('sql/analytics', f)
  if (f.startsWith('00_')) { console.log('views ok      ', f); continue }
  const ultimo = res[res.length - 1]
  // A pergunta é o primeiro parágrafo de comentário, até a linha "Técnicas:".
  const pergunta = sql
    .split('\n')
    .filter((l) => l.startsWith('--'))
    .map((l) => l.replace(/^--\s?/, '').trim())
    .join(' ')
    .split(/Técnicas:/)[0]
    .replace(/^Pergunta:\s*/, '')
    .trim()
  md += `## ${f.replace('.sql', '')}\n\n_${pergunta}_ — [ver SQL](../sql/analytics/${f})\n\n${tabela(ultimo)}\n`
  console.log('análise ok    ', f, `(${ultimo.rows.length} linhas)`)
}

writeFileSync(join(raiz, 'docs', 'resultados.md'), md)
console.log(`\nPronto em ${((Date.now() - t0) / 1000).toFixed(1)}s → docs/resultados.md`)
