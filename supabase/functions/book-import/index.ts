// Deki book-import: server-side, resumable, throttled import of legal open books (links only).
// Called every 2 minutes by pg_cron (part42) with a shared secret. Verify JWT must be OFF.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically. No other secret needed.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const json = (o: unknown) => new Response(JSON.stringify(o), { headers: { ...cors, 'Content-Type': 'application/json' } });

type Book = { title: string; author: string; link: string; cover: string | null; license: string; rights_url: string | null; lang: string; quality: number; subjects: string };
class RateLimited extends Error {}

// Strict per-item rights gate. Only CC0, CC BY, CC BY-SA and public domain are auto-published.
// NC, ND, "all rights reserved", unknown, empty or generic labels stay in review.
function rightsLabel(license: string, rightsUrl: string | null): string | null {
  const url = String(rightsUrl ?? '').toLowerCase();
  const m = url.match(/creativecommons\.org\/(licenses|publicdomain)\/([a-z-]+)\/?([0-9.]*)/);
  if (m) {
    const [, kind, code, ver] = m;
    if (kind === 'publicdomain') return code === 'zero' ? 'CC0' : code === 'mark' ? 'Public domain' : null;
    if (code === 'by') return `CC BY${ver ? ' ' + ver : ''}`;
    if (code === 'by-sa') return `CC BY-SA${ver ? ' ' + ver : ''}`;
    return null; // by-nc, by-nd, by-nc-sa, by-nc-nd ...
  }
  const t = String(license ?? '').toLowerCase().replace(/[_]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t) return null;
  if (/non ?-?commercial|no ?-?deriv|\bnc\b|\bnd\b|by-nc|by-nd|all rights|unknown|review|licen[cs]e per|verify|\/|\bor\b/.test(t)) return null;
  if (/^(cc0( 1\.0)?|public domain( \(cc0\))?|public domain mark( 1\.0)?)$/.test(t)) return t.startsWith('cc0') ? 'CC0' : 'Public domain';
  let v = t.match(/^cc[ -]by[ -]sa(?: ([0-9.]+))?$/) ?? t.match(/^creative commons attribution[ -]share ?alike(?: licen[cs]e)?(?: ([0-9.]+))?$/);
  if (v) return `CC BY-SA${v[1] ? ' ' + v[1] : ''}`;
  v = t.match(/^cc[ -]by(?: ([0-9.]+))?$/) ?? t.match(/^creative commons attribution(?: licen[cs]e)?(?: ([0-9.]+))?$/);
  if (v) return `CC BY${v[1] ? ' ' + v[1] : ''}`;
  return null;
}

async function getJson(url: string, headers: Record<string, string> = {}): Promise<any> {
  const r = await fetch(url, { headers: { 'User-Agent': 'DekiBookImport/1.0 (education app; open licences only)', ...headers }, signal: AbortSignal.timeout(20000) });
  if (r.status === 429 || r.status === 503) throw new RateLimited(`HTTP ${r.status}`);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return await r.json();
}
const first = (v: any) => (Array.isArray(v) ? v[0] : v);
const txt = (v: any) => (Array.isArray(v) ? v.join(', ') : String(v ?? ''));
const dig = (o: any, path: string) => path.split('.').filter(Boolean).reduce((a: any, k) => (a == null ? undefined : a[k]), o);

// ---------- providers: each returns one page of books and the next cursor (null = finished) ----------
async function archive(s: any, cur: any, size: number): Promise<{ books: Book[]; next: any }> {
  const page = Number(cur.page ?? 1);
  const resync = cur.mode === 'new';
  if (resync && page > 2) return { books: [], next: null };
  let q = `(title:(${s.query}) OR subject:(${s.query})) AND mediatype:texts AND (licenseurl:*creativecommons* OR licenseurl:*publicdomain*)`;
  if (s.language === 'ar') q += ' AND language:(ara OR Arabic)';
  else q += ' AND language:(eng OR English)';
  const u = new URL('https://archive.org/advancedsearch.php');
  u.searchParams.set('q', q);
  for (const f of ['identifier', 'title', 'creator', 'language', 'licenseurl', 'subject', 'downloads']) u.searchParams.append('fl[]', f);
  u.searchParams.set('rows', String(size));
  u.searchParams.set('page', String(page));
  u.searchParams.set('sort[]', resync ? 'addeddate desc' : 'downloads desc');
  u.searchParams.set('output', 'json');
  const j = await getJson(u.toString());
  const docs: any[] = j?.response?.docs ?? [];
  const books = docs.map((d) => {
    const id = String(d.identifier);
    const lic = txt(first(d.licenseurl));
    return {
      title: String(first(d.title) ?? id), author: txt(d.creator), link: `https://archive.org/details/${id}`,
      cover: `https://archive.org/services/img/${id}`, license: lic,
      rights_url: lic || null, lang: s.language, quality: Math.round(Math.log10(Number(d.downloads ?? 0) + 1) * 10),
      subjects: txt(d.subject),
    } as Book;
  });
  return { books, next: docs.length < size ? null : { page: page + 1, mode: cur.mode } };
}

async function openstax(_s: any, cur: any, size: number): Promise<{ books: Book[]; next: any }> {
  const u = 'https://openstax.org/apps/cms/api/v2/pages/?type=books.Book&fields=title,cover_url,book_state,webview_rex_link,license_name,high_resolution_pdf_url&limit=200';
  const j = await getJson(u);
  const all: any[] = (j.items ?? []).filter((d: any) => d.book_state === 'live' && (d.webview_rex_link || d.high_resolution_pdf_url));
  const off = Number(cur.offset ?? 0);
  const part = all.slice(off, off + size);
  const books = part.map((d: any) => ({
    title: String(d.title), author: 'OpenStax', link: String(d.high_resolution_pdf_url || d.webview_rex_link),
    cover: d.cover_url || null, license: String(d.license_name ?? ''), rights_url: String(d.webview_rex_link || '') || null,
    lang: 'en', quality: 100, subjects: String(d.title),
  } as Book));
  return { books, next: off + size >= all.length ? null : { offset: off + size } };
}

async function wikisource(s: any, cur: any, size: number): Promise<{ books: Book[]; next: any }> {
  const host = s.language === 'ar' ? 'ar.wikisource.org' : 'en.wikisource.org';
  const off = Number(cur.offset ?? 0);
  const u = `https://${host}/w/api.php?action=query&list=search&srsearch=${encodeURIComponent(s.query)}&srnamespace=0&srlimit=${Math.min(size, 50)}&sroffset=${off}&format=json`;
  const j = await getJson(u);
  const rows: any[] = j?.query?.search ?? [];
  const books = rows.map((d) => ({
    title: String(d.title), author: 'Wikisource', link: `https://${host}/wiki/${encodeURIComponent(String(d.title).replace(/ /g, '_'))}`,
    cover: null, license: 'Wikisource (licence per page, verify)', rights_url: `https://${host}/wiki/Wikisource:Copyright_policy`,
    lang: s.language, quality: 20, subjects: String(d.title),
  } as Book));
  return { books, next: j?.continue?.sroffset != null ? { offset: j.continue.sroffset } : null };
}

async function ncbi(s: any, cur: any, size: number): Promise<{ books: Book[]; next: any }> {
  const mark = String(cur.mark ?? '*');
  const u = `https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=${encodeURIComponent(`${s.query} AND OPEN_ACCESS:y AND SRC:MED AND HAS_BOOK:y`)}&format=json&resultType=core&pageSize=${size}&cursorMark=${encodeURIComponent(mark)}`;
  const j = await getJson(u);
  const rows: any[] = j?.resultList?.result ?? [];
  const books: Book[] = [];
  for (const d of rows) {
    const b = String(d.bookid ?? '');
    if (!b) continue;
    books.push({
      title: String(d.title ?? '').replace(/<[^>]*>/g, ''), author: String(d.authorString ?? ''), link: `https://www.ncbi.nlm.nih.gov/books/${b}/`,
      cover: null, license: String(d.license ?? 'NCBI Bookshelf (licence per book page)'), rights_url: `https://www.ncbi.nlm.nih.gov/books/${b}/`,
      lang: 'en', quality: 60, subjects: String(d.title ?? ''),
    });
  }
  const nm = j?.nextCursorMark;
  return { books, next: !nm || nm === mark || rows.length < size ? null : { mark: nm } };
}

async function custom(s: any, cur: any, size: number): Promise<{ books: Book[]; next: any }> {
  // Admin-defined JSON API. api_url may contain {q} and {page}. Only https. field_map uses dotted paths.
  const page = Number(cur.page ?? 1);
  const url = String(s.api_url ?? '').replace('{q}', encodeURIComponent(s.query)).replace('{page}', String(page));
  if (!url.startsWith('https://')) throw new Error('custom source must be https');
  const hdr: Record<string, string> = {};
  if (s.api_key) hdr['Authorization'] = `Bearer ${s.api_key}`;
  const j = await getJson(url, hdr);
  const fm = s.field_map ?? {};
  const list: any[] = fm.items ? dig(j, fm.items) : Array.isArray(j) ? j : j?.results ?? j?.items ?? j?.docs ?? [];
  const books = (list ?? []).slice(0, size).map((d) => ({
    title: txt(dig(d, fm.title ?? 'title')), author: txt(dig(d, fm.author ?? 'author')), link: txt(dig(d, fm.link ?? 'link')),
    cover: txt(dig(d, fm.cover ?? 'cover')) || null, license: txt(dig(d, fm.license ?? 'license')), rights_url: null,
    lang: s.language, quality: 30, subjects: txt(dig(d, fm.title ?? 'title')),
  } as Book)).filter((b) => b.title && b.link.startsWith('http'));
  return { books, next: (list ?? []).length < size ? null : { page: page + 1 } };
}

const PROVIDERS: Record<string, any> = { archive, openstax, wikisource, ncbi, custom };

function categorize(b: Book, cats: any[], prior: string | null): string {
  if (prior) return prior;
  const t = `${b.title} ${b.subjects}`.toLowerCase();
  let best = 'general', score = 0;
  for (const c of cats) {
    if (c.hidden || c.key === 'general') continue;
    let sc = 0;
    for (const k of c.keywords ?? []) if (k && t.includes(String(k).toLowerCase())) sc++;
    if (sc > score) { score = sc; best = c.key; }
  }
  return best;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const body = await req.json();
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: sec } = await db.from('quiz_auto_secret').select('secret').limit(1).maybeSingle();
    if (!sec || sec.secret !== body.secret) return json({ error: 'auth' });
    const t = String(body.tenant_id ?? '');
    if (!t) return json({ error: 'no_tenant' });
    const now = new Date();
    const iso = now.toISOString();

    // Throttle: books per hour, then a break.
    const { data: st } = await db.from('book_import_settings').select('*').eq('tenant_id', t).maybeSingle();
    if (!st) return json({ skipped: 'no_settings' });
    if (st.paused_until && new Date(st.paused_until) > now) return json({ skipped: 'break' });
    let wStart = st.window_start ? new Date(st.window_start) : null;
    let wCount = Number(st.window_count ?? 0);
    if (!wStart || now.getTime() - wStart.getTime() > 3600000) { wStart = now; wCount = 0; }
    if (wCount >= st.books_per_hour) {
      await db.from('book_import_settings').update({ paused_until: new Date(now.getTime() + st.break_minutes * 60000).toISOString(), window_start: null, window_count: 0 }).eq('tenant_id', t);
      return json({ skipped: 'hour_limit' });
    }

    // Wake finished sources for the daily "new books" re-sync.
    await db.from('book_sources').update({ status: 'running', enabled: true, cursor: { mode: 'new' }, next_sync_at: null })
      .eq('tenant_id', t).eq('status', 'done').lt('next_sync_at', iso);

    // Pick the least recently served source that is due.
    const { data: srcs } = await db.from('book_sources').select('*').eq('tenant_id', t).eq('enabled', true)
      .or(`paused_until.is.null,paused_until.lt.${iso}`).in('status', ['queued', 'preview', 'running'])
      .order('last_run', { ascending: true, nullsFirst: true }).limit(1);
    const s = srcs?.[0];
    if (!s) return json({ idle: true });

    const preview = s.status === 'queued';
    const size = preview ? 10 : Math.min(Number(st.batch_size ?? 40), Math.max(1, st.books_per_hour - wCount));
    await db.from('book_sources').update({ last_run: iso, status: preview ? 'preview' : 'running' }).eq('id', s.id);
    const prov = PROVIDERS[s.kind];
    if (!prov) { await db.from('book_sources').update({ status: 'error', enabled: false, last_error: 'unknown kind' }).eq('id', s.id); return json({ error: 'kind' }); }

    let res: { books: Book[]; next: any };
    try {
      res = await prov(s, s.cursor ?? {}, size);
    } catch (e) {
      if (e instanceof RateLimited) {
        await db.from('book_sources').update({ paused_until: new Date(now.getTime() + 15 * 60000).toISOString(), last_error: `rate limited (${String(e.message)}), retrying in 15 min` }).eq('id', s.id);
        return json({ backoff: s.key });
      }
      await db.from('book_sources').update({ status: 'error', last_error: String(e).slice(0, 300) }).eq('id', s.id);
      return json({ error: String(e).slice(0, 200) });
    }

    // Dedupe against what is already in the library, then insert.
    const links = res.books.map((b) => b.link);
    const have = new Set<string>();
    if (links.length) {
      const { data: ex } = await db.from('library_items').select('file_url').eq('tenant_id', t).in('file_url', links);
      for (const r of ex ?? []) have.add(r.file_url);
    }
    const { data: cats } = await db.from('library_categories').select('key,keywords,hidden').eq('tenant_id', t);
    const seen = new Set<string>();
    const rows: any[] = [];
    let review = 0;
    for (const b of res.books) {
      if (have.has(b.link) || seen.has(b.link)) continue;
      seen.add(b.link);
      const label = rightsLabel(b.license, b.rights_url);
      const published = label !== null && st.auto_publish_open !== false;
      if (label) b.license = label;
      if (!published) review++;
      rows.push({
        tenant_id: t, title: b.title.slice(0, 300), file_url: b.link, file_type: 'link', kind: 'book',
        author: b.author.slice(0, 300), cover_url: b.cover, license: b.license.slice(0, 200) || 'Unknown (review)', source: s.kind === 'custom' ? s.label : new URL(b.link).hostname,
        language: b.lang === 'ar' ? 'ar' : 'en', category: categorize(b, cats ?? [], s.category), rights_url: b.rights_url,
        source_key: s.key, quality: b.quality, status: published ? 'published' : 'review', added_at: iso,
      });
    }
    let added = 0;
    if (rows.length) {
      const { error } = await db.from('library_items').insert(rows);
      if (error) {
        await db.from('book_sources').update({ status: 'error', last_error: `insert: ${error.message}`.slice(0, 300) }).eq('id', s.id);
        return json({ error: 'insert', detail: error.message });
      }
      added = rows.length;
    }
    const total = Number(s.imported ?? 0) + added;
    const finished = res.next == null || total >= Number(s.cap ?? 300);
    await db.from('book_sources').update({
      imported: total, review_count: Number(s.review_count ?? 0) + review, cursor: finished ? {} : res.next,
      status: finished ? 'done' : 'running', last_error: null,
      next_sync_at: finished ? new Date(now.getTime() + 24 * 3600000).toISOString() : null,
    }).eq('id', s.id);
    await db.from('book_import_settings').update({ window_start: wStart.toISOString(), window_count: wCount + added }).eq('tenant_id', t);
    return json({ source: s.key, added, preview, finished });
  } catch (e) {
    console.error('book-import', String(e));
    return json({ error: 'handler', detail: String(e).slice(0, 300) });
  }
});
