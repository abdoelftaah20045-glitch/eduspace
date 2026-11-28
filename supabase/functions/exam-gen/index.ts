// Deki exam generator from uploaded files (Google Gemini free tier).
// Admin picks PDF / text files in the app. "create" uploads them to Gemini's file store (kept 48 h by Google,
// nothing is stored on our server) and saves a job. The database timer then calls this function every minute with
// {auto:true, job_id, secret}; each call writes one batch of questions into the exam, until the target is reached,
// the admin stops it, or the free quota pauses it (it resumes by itself).
// Secret needed: GEMINI_API_KEY. SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are provided.
// Deploy with "Verify JWT" OFF (same as quiz-gen): the timer calls it with a shared secret instead.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { decodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, 'Content-Type': 'application/json' } });
const BASE = 'https://generativelanguage.googleapis.com/v1beta';
const UPLOAD = 'https://generativelanguage.googleapis.com/upload/v1beta/files';
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const badUntil = new Map<string, number>();
const isBad = (m: string) => (badUntil.get(m) ?? 0) > Date.now();

async function pickModels(key: string): Promise<string[]> {
  const fixed = ['gemini-flash-lite-latest', 'gemini-flash-latest'];
  try {
    const listed0: any[] = [];
    let token = '';
    for (let i = 0; i < 4; i++) {
      const r = await fetch(`${BASE}/models?pageSize=200${token ? `&pageToken=${token}` : ''}&key=${key}`, { signal: AbortSignal.timeout(8000) });
      const j = await r.json();
      listed0.push(...(j?.models ?? []));
      token = j?.nextPageToken ?? '';
      if (!token) break;
    }
    const ver = (n: string) => parseFloat((n.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? '0');
    const listed: string[] = listed0
      .filter((m: any) => (m.supportedGenerationMethods ?? []).includes('generateContent'))
      .map((m: any) => String(m.name).replace('models/', ''))
      .filter((n: string) => /gemini/.test(n) && /(flash|lite|latest)/.test(n) && !/(image|tts|live|audio|embed|robotics|computer|vision|imagen|veo|aqa)/.test(n));
    const rank = (n: string) => (/lite|8b/.test(n) ? 0 : 1);
    const all = [...new Set(listed)].sort((a, b) => rank(a) - rank(b) || ver(b) - ver(a) || a.length - b.length);
    if (!all.length) return fixed;
    const ok = all.filter((m) => !isBad(m));
    return (ok.length ? ok : all).slice(0, 6);
  } catch (_) {
    return fixed;
  }
}

function quotaInfo(j: any): { perDay: boolean; waitMs: number } {
  const details: any[] = j?.error?.details ?? [];
  let perDay = /per ?day|daily/i.test(String(j?.error?.message ?? '')) || /limit:\s*0\b/.test(JSON.stringify(j?.error ?? {}));
  let waitMs = 20000;
  for (const d of details) {
    for (const v of d?.violations ?? []) if (/PerDay/i.test(String(v?.quotaId ?? ''))) perDay = true;
    const m = String(d?.retryDelay ?? '').match(/(\d+(?:\.\d+)?)s/);
    if (m) waitMs = Math.min(45000, Math.ceil(parseFloat(m[1]) * 1000) + 1000);
  }
  return { perDay, waitMs };
}

// Upload one file to Gemini's file store; returns its uri once it is ACTIVE.
async function uploadFile(key: string, name: string, mime: string, bytes: Uint8Array) {
  const start = await fetch(`${UPLOAD}?key=${key}`, {
    method: 'POST',
    headers: {
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': String(bytes.length),
      'X-Goog-Upload-Header-Content-Type': mime,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ file: { display_name: name.slice(0, 80) } }),
    signal: AbortSignal.timeout(20000),
  });
  const url = start.headers.get('x-goog-upload-url');
  if (!url) throw new Error(`upload_start ${start.status} ${(await start.text()).slice(0, 120)}`);
  const fin = await fetch(url, {
    method: 'POST',
    headers: { 'X-Goog-Upload-Offset': '0', 'X-Goog-Upload-Command': 'upload, finalize', 'Content-Length': String(bytes.length) },
    body: bytes,
    signal: AbortSignal.timeout(90000),
  });
  const fj = await fin.json();
  const f = fj?.file;
  if (!f?.uri) throw new Error(`upload ${fin.status} ${JSON.stringify(fj).slice(0, 120)}`);
  let state = f.state ?? 'ACTIVE';
  for (let i = 0; i < 20 && state === 'PROCESSING'; i++) {
    await sleep(2000);
    const g = await (await fetch(`${BASE}/${f.name}?key=${key}`)).json();
    state = g?.state ?? 'ACTIVE';
  }
  if (state === 'FAILED') throw new Error('file_failed');
  return { uri: String(f.uri), mime: String(f.mimeType ?? mime), name };
}

const schema = {
  type: 'OBJECT',
  properties: {
    questions: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          question: { type: 'STRING' },
          options: { type: 'ARRAY', items: { type: 'STRING' } },
          correct: { type: 'INTEGER' },
          explanation: { type: 'STRING' },
        },
        required: ['question', 'options', 'correct', 'explanation'],
      },
    },
  },
  required: ['questions'],
};

const norm = (s: string) => s.toLowerCase().replace(/[\s\p{P}]+/g, ' ').trim();

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const key = Deno.env.get('GEMINI_API_KEY');
    if (!key) return json({ error: 'no_key' });
    const body = await req.json();

    // ---------- create: called by the admin from the app ----------
    if (body.action === 'create') {
      const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      });
      const { data: u } = await db.auth.getUser();
      if (!u?.user) return json({ error: 'auth' });
      const tenantId = String(body.tenant_id ?? '');
      const title = String(body.title ?? '').trim().slice(0, 200);
      const total = Math.min(600, Math.max(10, Number(body.total ?? 100)));
      const files: any[] = Array.isArray(body.files) ? body.files.slice(0, 6) : [];
      if (!tenantId || !title || !files.length) return json({ error: 'missing' });
      // Admin check first (no upload before we know the caller may create exams).
      const { data: ex, error: e1 } = await db.from('exams').insert({
        tenant_id: tenantId, title, description: String(body.description ?? '').trim() ||
          (body.mode === 'import' ? 'أسئلة مستوردة من ملف. راجعها قبل النشر.' : 'امتحان مولّد بالذكاء الاصطناعي من ملفات المادة. راجع الأسئلة قبل النشر.'),
        status: 'draft', pass_grade: Math.ceil(total * 0.6), max_attempts: 3, created_by: u.user.id,
      }).select('id').single();
      if (e1 || !ex) return json({ error: 'not_allowed', detail: String(e1?.message ?? '') });
      const uris: any[] = [];
      try {
        for (const f of files) {
          const bytes = decodeBase64(String(f.b64 ?? ''));
          const mime = /pdf/i.test(String(f.mime)) || /\.pdf$/i.test(String(f.name)) ? 'application/pdf' : 'text/plain';
          uris.push(await uploadFile(key, String(f.name ?? 'file'), mime, bytes));
        }
      } catch (e) {
        await db.from('exams').delete().eq('id', ex.id);
        return json({ error: 'upload', detail: String(e).slice(0, 200) });
      }
      const { data: job, error: e2 } = await db.from('exam_gen_jobs').insert({
        tenant_id: tenantId, exam_id: ex.id, title, total, file_uris: uris,
        language: String(body.language ?? 'auto'), mode: body.mode === 'import' ? 'import' : 'generate', status: 'queued', created_by: u.user.id,
      }).select('id').single();
      if (e2 || !job) return json({ error: 'job', detail: String(e2?.message ?? '') });
      return json({ ok: true, job_id: job.id, exam_id: ex.id, files: uris.length });
    }

    // ---------- auto: called by the database timer ----------
    if (body.auto !== true) return json({ error: 'bad_request' });
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: sec } = await db.from('quiz_auto_secret').select('secret').limit(1).maybeSingle();
    if (!sec || sec.secret !== body.secret) return json({ error: 'auth' });
    const nowIso = new Date().toISOString();
    const { data: job } = await db.from('exam_gen_jobs')
      .update({ busy_until: new Date(Date.now() + 3 * 60000).toISOString(), status: 'running', updated_at: nowIso })
      .eq('id', String(body.job_id ?? '')).in('status', ['queued', 'running']).eq('stop', false)
      .or(`busy_until.is.null,busy_until.lt.${nowIso}`)
      .or(`paused_until.is.null,paused_until.lt.${nowIso}`)
      .select('*').maybeSingle();
    if (!job) return json({ skipped: 'not_due' });
    const release = async (upd: any) => {
      await db.from('exam_gen_jobs').update({ busy_until: null, updated_at: new Date().toISOString(), ...upd }).eq('id', job.id);
    };

    const { data: eq } = await db.from('exam_questions').select('questions(body)').eq('exam_id', job.exam_id).limit(1000);
    const have = new Set<string>((eq ?? []).map((r: any) => norm(String(r?.questions?.body ?? ''))).filter(Boolean));
    const made0 = have.size;
    if (made0 >= job.total) {
      await release({ status: 'done', made: made0, last_error: null });
      return json({ done: true });
    }
    const batch = Math.min(job.batch ?? 20, job.total - made0);
    // Spread the batches over the whole documents: batch k focuses on its slice.
    const from = Math.floor((made0 / job.total) * 100);
    const to = Math.min(100, Math.ceil(((made0 + batch) / job.total) * 100));
    const recent = [...have].slice(-25);
    const lang = job.language && job.language !== 'auto' ? `Write in ${job.language === 'ar' ? 'Arabic' : 'English'}.` : 'Write in the language of the documents (Arabic stays Arabic).';
    const prompt = job.mode === 'import'
      ? `Exam: ${job.title}\nThe attached document(s) already contain exam questions (a question bank, maybe with an answer key at the end or after each question). ` +
        `EXTRACT up to ${batch} questions from about ${from}% to ${to}% of the document's length (by position). Copy each question and its options exactly as written, do not rewrite or invent. ` +
        `Use the answer key or marks in the document for the correct option (index 0-3). If a question has no clear answer in the document, skip it. ` +
        `Keep only questions with exactly 4 options (skip other formats). ${lang} For explanation use the document's explanation if any, else a short one-sentence reason. ` +
        (recent.length ? `Skip these questions that are already saved:\n- ${recent.join('\n- ')}\n` : '')
      :
      `Exam: ${job.title}\nUsing ONLY the attached document(s), write ${batch} NEW multiple-choice questions. ` +
      `Cover the part of the material from about ${from}% to ${to}% of its length (by position), and also anything important in that part. ` +
      `${lang} Test understanding of the material, not page numbers or file names. Do not invent facts that are not in the documents. ` +
      `Each question has exactly 4 options, exactly one correct (index 0-3), and a one-sentence explanation from the documents. ` +
      (recent.length ? `Do NOT repeat or rephrase these questions already written:\n- ${recent.join('\n- ')}\n` : '');
    const parts: any[] = [...(job.file_uris ?? []).map((f: any) => ({ fileData: { fileUri: f.uri, mimeType: f.mime } })), { text: prompt }];

    let qs: any[] | null = null;
    const errs: string[] = [];
    let quotaHit = false;
    let fileGone = false;
    const started = Date.now();
    const models = await pickModels(key);
    for (const model of models) {
      for (let attempt = 0; attempt < 2 && !qs; attempt++) {
        if (Date.now() - started > 120000) break;
        try {
          const r = await fetch(`${BASE}/models/${model}:generateContent?key=${key}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              contents: [{ role: 'user', parts }],
              generationConfig: { responseMimeType: 'application/json', responseSchema: schema, temperature: 0.4, maxOutputTokens: 14000 },
            }),
            signal: AbortSignal.timeout(100000),
          });
          const j = await r.json();
          const t = (j?.candidates?.[0]?.content?.parts ?? []).filter((p: any) => !p.thought).map((p: any) => p.text ?? '').join('');
          if (t) { qs = JSON.parse(t).questions ?? []; break; }
          const em = String(j?.error?.message ?? 'empty');
          errs.push(`${model}: ${r.status} ${em.slice(0, 80)}`);
          if (r.status === 429) {
            quotaHit = true;
            const qi = quotaInfo(j);
            if (qi.perDay) { badUntil.set(model, Date.now() + 6 * 3600000); break; }
            if (attempt === 0 && Date.now() - started + qi.waitMs < 110000) { await sleep(qi.waitMs); continue; }
            break;
          }
          if (r.status === 403 || r.status === 404) {
            if (/file|permission|not found/i.test(em) && /files\//i.test(em)) fileGone = true;
            badUntil.set(model, Date.now() + 6 * 3600000); break;
          }
          if (r.status === 503 || r.status === 500) { await sleep(1500); continue; }
          break;
        } catch (e) { errs.push(`${model}: ${String(e).slice(0, 60)}`); break; }
      }
      if (qs) break;
    }
    if (qs === null) {
      if (fileGone) { await release({ status: 'error', stop: true, last_error: 'الملفات انتهت صلاحيتها عند جوجل (48 ساعة). ارفعها تاني.' }); return json({ error: 'file_expired' }); }
      if (quotaHit) { await release({ paused_until: new Date(Date.now() + 60 * 60000).toISOString(), last_error: 'quota: وقفة ساعة، بيكمل لوحده (حد جوجل المجاني)' }); return json({ quota: true }); }
      await release({ paused_until: new Date(Date.now() + 5 * 60000).toISOString(), last_error: errs.join(' | ').slice(0, 300) });
      return json({ error: 'gemini' });
    }
    const good = qs.filter((q) =>
      q && typeof q.question === 'string' && q.question.trim() && Array.isArray(q.options) &&
      q.options.length === 4 && q.options.every((o: any) => typeof o === 'string' && o.trim()) &&
      Number.isInteger(q.correct) && q.correct >= 0 && q.correct <= 3 &&
      new Set(q.options.map((o: string) => o.trim())).size === 4 && !have.has(norm(q.question)));
    let order = made0;
    let added = 0;
    for (const q of good) {
      if (made0 + added >= job.total) break;
      const { data: row, error: e2 } = await db.from('questions').insert({
        tenant_id: job.tenant_id, type: 'mcq', body: q.question.trim(), points: 1,
        explanation: String(q.explanation ?? '').trim() || null,
      }).select('id').single();
      if (e2 || !row) continue;
      await db.from('question_options').insert(
        q.options.map((o: string, i: number) => ({ question_id: row.id, body: o.trim(), is_correct: i === q.correct, sort_order: i })));
      await db.from('exam_questions').insert({ exam_id: job.exam_id, question_id: row.id, sort_order: order++ });
      added++;
    }
    const made = made0 + added;
    const fin = made >= job.total;
    // Two empty-ish batches in a row means the material is exhausted: finish with what we have.
    const stuck = added === 0 ? (job.empty_batches ?? 0) + 1 : 0;
    const exhausted = stuck >= 3;
    await release({
      made, empty_batches: stuck, last_error: added === 0 ? 'الدفعة الأخيرة ما فيهاش أسئلة جديدة' : null,
      status: fin || exhausted ? 'done' : 'running',
      ...(fin || exhausted ? {} : {}),
    });
    if (fin || exhausted) {
      await db.from('exams').update({ pass_grade: Math.ceil(made * 0.6) }).eq('id', job.exam_id);
    }
    return json({ ok: true, added, made, total: job.total, done: fin || exhausted });
  } catch (e) {
    return json({ error: 'exception', detail: String(e).slice(0, 200) });
  }
});
