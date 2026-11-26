// Deki study assistant (Google Gemini free tier). Lean version, no imports.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) return json({ error: "no_key" });
    const body = await req.json();
    const contents = (body.messages ?? []).slice(-10).map((m: any) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: String(m.text ?? "").slice(0, 2000) }],
    }));
    const system =
      `You are Deki, the smart assistant inside the Deki learning app. Reply in the user's language (${body.lang ?? "ar"}; Egyptian Arabic if Arabic), short, clear, friendly. Help with lessons, concepts, summaries, exam and study tips, planning, and using the app. For account, payments or grades, tell them to contact their organization admin. Never invent facts.`;
    const errs: string[] = [];
    for (const model of ["gemini-2.5-flash", "gemini-flash-latest"]) {
      const r = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ systemInstruction: { parts: [{ text: system }] }, contents }),
        },
      );
      const j = await r.json();
      const parts = j?.candidates?.[0]?.content?.parts ?? [];
      const text = parts.map((p: any) => p.text ?? "").join("").trim();
      if (text) return json({ text });
      errs.push(`${model}: ${r.status} ${j?.error?.message ?? "empty"}`);
    }
    return json({ error: "gemini", detail: errs.join(" | ").slice(0, 500) });
  } catch (e) {
    return json({ error: String(e) });
  }
});
