// Cloudflare Pages Function: POST /api/align
// On-demand alignment of a single Mishna via Claude Haiku.
// Set ANTHROPIC_API_KEY in Cloudflare Pages → Settings → Environment variables.

export async function onRequest(context) {
  const { request, env } = context;

  if (request.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'POST,OPTIONS',
        'access-control-allow-headers': 'content-type'
      }
    });
  }

  if (request.method !== 'POST') {
    return jsonError('Method not allowed', 405);
  }

  if (!env.ANTHROPIC_API_KEY) {
    return jsonError('ANTHROPIC_API_KEY not configured on the server.', 500);
  }

  let body;
  try { body = await request.json(); }
  catch { return jsonError('Invalid JSON body', 400); }

  const { tractate, chapter, mishna } = body;
  if (!tractate || !chapter || !mishna) {
    return jsonError('Missing tractate, chapter, or mishna', 400);
  }

  try {
    // 1) Fetch from Sefaria (William Davidson, fall back to Kulp if empty)
    const fetchSefaria = async (ven) => {
      const url = `https://www.sefaria.org/api/texts/Mishnah_${tractate}.${chapter}?context=0&commentary=0&ven=${encodeURIComponent(ven)}&vlang=english`;
      const r = await fetch(url);
      return r.json();
    };

    let sef = await fetchSefaria('William_Davidson_Edition_-_English');
    const idx = mishna - 1;
    const enExists = Array.isArray(sef.text) && sef.text[idx] && String(sef.text[idx]).trim().length > 10;
    if (!enExists) {
      const alt = await fetchSefaria('Mishnah_Yomit_by_Dr._Joshua_Kulp');
      if (alt && alt.text) sef.text = alt.text;
    }

    const heRaw = Array.isArray(sef.he) ? sef.he[idx] : sef.he;
    const enRaw = Array.isArray(sef.text) ? sef.text[idx] : sef.text;
    if (!heRaw) return jsonError('Mishna not found at Sefaria', 404);

    const he = String(heRaw).replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
    const enHtml = String(enRaw || '').replace(/\s+/g, ' ').trim();
    const hasBold = /<b>/i.test(enHtml);

    const enRule = hasBold
      ? '- For `en`: include ONLY the text that appeared INSIDE <b>...</b> tags in the English input, joined naturally, that corresponds to that Hebrew phrase. STRIP every HTML tag from the output. NEVER include text that was outside <b> tags. NO commentary, NO Steinsaltz explanations.'
      : '- For `en`: extract the portion of the English that corresponds to that Hebrew phrase. The input is already clean translation; just split it appropriately. Strip any HTML.';

    const prompt = `Align this Hebrew Mishnah with its English translation.

Rules:
- A SEGMENT is a logical grouping: an opinion (e.g. \`the words of Rabbi X\`, \`Beit Shammai say\`), a story (starts with \`מעשה\`), a generalization (starts with \`ולא זו בלבד\`), or an unmarked block of related sentences. Use 1 segment if everything is one continuous thought.
- A PHRASE within a segment is one Hebrew sentence ending in a period. Merge sentences of 1-3 words into the nearest neighbor.
- Every Hebrew word from the input MUST appear in some phrase, in the original order, with original nikud preserved.
${enRule}
- If a Hebrew phrase has NO matching English, set \`en\` to "". Do NOT invent translation.
- Output MUST be valid JSON. No markdown fences, no prose before or after.

Hebrew:
${he}

English:
${enHtml}

Output (JSON array only):
[{"phrases":[{"he":"...","en":"..."}, ...]}, ...]`;

    // 2) Call Claude Haiku
    const claudeResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 4096,
        messages: [{ role: 'user', content: prompt }]
      })
    });

    const data = await claudeResp.json();
    if (!claudeResp.ok || data.error) {
      const msg = data.error && data.error.message ? data.error.message : 'Claude API error';
      return jsonError(msg, 502);
    }

    // 3) Parse Claude's JSON response
    let raw = data.content[0].text;
    raw = raw.replace(/```(?:json)?\s*/g, '').replace(/```/g, '').trim();
    const start = raw.indexOf('[');
    const end = raw.lastIndexOf(']');
    if (start >= 0 && end > start) raw = raw.substring(start, end + 1);
    let segments;
    try { segments = JSON.parse(raw); }
    catch {
      const fixed = raw.replace(/,(\s*[\]}])/g, '$1');
      segments = JSON.parse(fixed);
    }

    if (!Array.isArray(segments) || !segments[0] || !segments[0].phrases) {
      return jsonError('Claude returned unexpected shape', 502);
    }

    return new Response(JSON.stringify({ segments }), {
      headers: {
        'content-type': 'application/json',
        'access-control-allow-origin': '*'
      }
    });
  } catch (err) {
    return jsonError(err.message || String(err), 500);
  }
}

function jsonError(msg, status) {
  return new Response(JSON.stringify({ error: msg }), {
    status,
    headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': '*'
    }
  });
}
